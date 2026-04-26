#!/usr/bin/env bash
# =============================================================================
# OTS — DB Schema 初始化（透過 Cloud Run Job，不需 public IP）
# 使用方式：./init-db.sh [dev|staging|production]
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

ENV="${1:-}"
[[ "$ENV" =~ ^(dev|staging|production)$ ]] || \
  err "請指定環境：./init-db.sh [dev|staging|production]"

PROJECT_ID="ots-translation"
REGION="asia-east1"
SQL_INSTANCE="ots-db-${ENV}"
SQL_DATABASE="ots"
SQL_APP_USER="ots_app"
SA_PIPELINE_EMAIL="ots-pipeline-${ENV}@${PROJECT_ID}.iam.gserviceaccount.com"
INSTANCE_CONNECTION="${PROJECT_ID}:${REGION}:${SQL_INSTANCE}"
JOB_NAME="ots-db-init-${ENV}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ -f "${SCRIPT_DIR}/sql/schema.sql" ]] || err "找不到 sql/schema.sql"

log "環境：$ENV / Instance：$SQL_INSTANCE"

if [[ "$ENV" == "production" ]]; then
  warn "即將初始化 PRODUCTION DB，確認後按 Enter 繼續，Ctrl+C 取消..."
  read -r
fi

# schema.sql → base64（單行，傳入 Cloud Run Job 環境變數）
log "準備 schema.sql..."
SCHEMA_B64=$(base64 -w0 "${SCRIPT_DIR}/sql/schema.sql")

# Cloud Run Job 內執行的 shell 指令：
#   1. 等待 Auth Proxy socket 出現（最多 60 秒）
#   2. socket ready 後執行 psql
ENTRYPOINT_CMD='
SOCKET="/cloudsql/${INSTANCE_CONNECTION}/.s.PGSQL.5432"
echo "Waiting for Auth Proxy socket: $SOCKET"
i=0
while [ ! -S "$SOCKET" ]; do
  i=$(expr $i + 1)
  [ $i -ge 30 ] && echo "ERROR: socket not ready after 60s" && exit 1
  echo "  waiting... ($i/30)"
  sleep 2
done
echo "Socket ready. Running schema..."
echo "$SCHEMA_B64" | base64 -d | psql
echo "Done."
'

# 刪除舊 Job（若存在）
if gcloud run jobs describe "$JOB_NAME" \
     --region="$REGION" --project="$PROJECT_ID" --quiet &>/dev/null; then
  log "刪除舊 Job：$JOB_NAME ..."
  gcloud run jobs delete "$JOB_NAME" \
    --region="$REGION" --project="$PROJECT_ID" --quiet
fi

# 建立 Job
log "建立 Cloud Run Job：$JOB_NAME ..."
gcloud run jobs create "$JOB_NAME" \
  --image="postgres:15-alpine" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --service-account="$SA_PIPELINE_EMAIL" \
  --set-cloudsql-instances="$INSTANCE_CONNECTION" \
  --network=default \
  --subnet=default \
  --vpc-egress=private-ranges-only \
  --set-env-vars="INSTANCE_CONNECTION=${INSTANCE_CONNECTION}" \
  --set-env-vars="PGDATABASE=${SQL_DATABASE}" \
  --set-env-vars="PGUSER=${SQL_APP_USER}" \
  --set-env-vars="PGHOST=/cloudsql/${INSTANCE_CONNECTION}" \
  --set-secrets="PGPASSWORD=ots-db-password-${ENV}:latest" \
  --set-env-vars="SCHEMA_B64=${SCHEMA_B64}" \
  --command="/bin/sh" \
  --args="-c,${ENTRYPOINT_CMD}" \
  --max-retries=0 \
  --task-timeout=300 \
  --quiet

# 執行 Job（同步等待）
log "執行 Job（同步等待完成）..."
gcloud run jobs execute "$JOB_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --wait

# 確認結果
EXECUTION=$(gcloud run jobs executions list \
  --job="$JOB_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --limit=1 \
  --format="value(name)")

STATUS=$(gcloud run jobs executions describe "$EXECUTION" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format="value(status.conditions[0].type)")

if [[ "$STATUS" == "Completed" ]]; then
  ok "DB Schema 初始化完成：$SQL_INSTANCE / $SQL_DATABASE"
  log "清除 Job..."
  gcloud run jobs delete "$JOB_NAME" \
    --region="$REGION" --project="$PROJECT_ID" --quiet
  ok "完成"
else
  err "Job 失敗，查看 logs：
gcloud run jobs executions logs tail ${EXECUTION} --region=${REGION}"
fi
