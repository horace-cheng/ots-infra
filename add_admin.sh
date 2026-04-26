#!/usr/bin/env bash
# =============================================================================
# OTS — 建立第一個 Admin 用戶
# =============================================================================
# 使用方式：
#   ./add_admin.sh dev admin@ots.tw FIREBASE_UID [superadmin]
#
# FIREBASE_UID 從 Firebase Console → Authentication → Users 取得
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

ENV="${1:-}"
EMAIL="${2:-}"
UID_FIREBASE="${3:-}"
ROLE="${4:-admin}"

[[ "$ENV" =~ ^(dev|staging|production)$ ]] || \
  err "使用方式：./add_admin.sh [dev|staging|production] EMAIL FIREBASE_UID [admin|superadmin]"
[[ -n "$EMAIL" ]]        || err "請提供 Email"
[[ -n "$UID_FIREBASE" ]] || err "請提供 Firebase UID"
[[ "$ROLE" =~ ^(admin|superadmin)$ ]] || err "role 必須是 admin 或 superadmin"

PROJECT_ID="ots-translation"
REGION="asia-east1"
SQL_INSTANCE="ots-db-${ENV}"
SQL_DATABASE="ots"
SQL_APP_USER="ots_app"
DB_PASSWORD_FILE="$HOME/.ots-db-root-pw-${ENV}"

[[ -f "$DB_PASSWORD_FILE" ]] || err "找不到密碼檔：$DB_PASSWORD_FILE"
DB_APP_PASSWORD=$(cat "$DB_PASSWORD_FILE")

log "建立 Admin 用戶：$EMAIL ($ROLE) — 環境：$ENV"

# 使用 Cloud Run Job 執行 SQL（和 init-db.sh 相同方式，不需 public IP）
JOB_NAME="ots-add-admin-tmp-${ENV}"

SQL="INSERT INTO admin_users (uid_firebase, email, role, note)
VALUES ('${UID_FIREBASE}', '${EMAIL}', '${ROLE}', 'Created by add_admin.sh')
ON CONFLICT (uid_firebase) DO UPDATE
  SET email = EXCLUDED.email,
      role  = EXCLUDED.role,
      active = true;
SELECT id, email, role, active FROM admin_users WHERE uid_firebase = '${UID_FIREBASE}';"

SCHEMA_B64=$(echo "$SQL" | base64 -w0)
INSTANCE_CONNECTION="${PROJECT_ID}:${REGION}:${SQL_INSTANCE}"
SA_PIPELINE="ots-pipeline-${ENV}@${PROJECT_ID}.iam.gserviceaccount.com"

ENTRYPOINT_CMD="SOCKET=/cloudsql/${INSTANCE_CONNECTION}/.s.PGSQL.5432; i=0; while [ ! -S \"\$SOCKET\" ]; do i=\$(expr \$i + 1); [ \$i -ge 30 ] && echo 'socket timeout' && exit 1; sleep 2; done; echo \"$SCHEMA_B64\" | base64 -d | psql"

# 清除舊 Job
gcloud run jobs delete "$JOB_NAME" \
  --region="$REGION" --project="$PROJECT_ID" --quiet 2>/dev/null || true

# 建立並執行一次性 Job
gcloud run jobs create "$JOB_NAME" \
  --image="postgres:15-alpine" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --service-account="$SA_PIPELINE" \
  --set-cloudsql-instances="$INSTANCE_CONNECTION" \
  --network=default \
  --subnet=default \
  --vpc-egress=private-ranges-only \
  --set-env-vars="PGDATABASE=${SQL_DATABASE},PGUSER=${SQL_APP_USER},PGHOST=/cloudsql/${INSTANCE_CONNECTION},INSTANCE_CONNECTION=${INSTANCE_CONNECTION}" \
  --set-secrets="PGPASSWORD=ots-db-password-${ENV}:latest" \
  --set-env-vars="SCHEMA_B64=${SCHEMA_B64}" \
  --command="/bin/sh" \
  --args="-c,${ENTRYPOINT_CMD}" \
  --max-retries=0 \
  --task-timeout=120 \
  --quiet

log "執行 Job..."
gcloud run jobs execute "$JOB_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --wait

# 清除 Job
gcloud run jobs delete "$JOB_NAME" \
  --region="$REGION" --project="$PROJECT_ID" --quiet

ok "Admin 建立完成：$EMAIL ($ROLE)"
echo ""
echo "  現在可以用這個帳號的 Firebase token 呼叫 /admin/* 端點"
