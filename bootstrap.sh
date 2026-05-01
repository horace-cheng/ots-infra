#!/usr/bin/env bash
# =============================================================================
# OTS Translation Service — Data Layer Bootstrap Script
# =============================================================================
# 用途：統一建立 dev / staging / production 三個環境的 Data Layer 初始設定
#       包含 Cloud SQL、Cloud Storage、Firestore、BigQuery、Secret Manager
#
# 使用方式：
#   ./bootstrap.sh dev
#   ./bootstrap.sh staging
#   ./bootstrap.sh production
#
# 前置條件：
#   1. 已安裝 gcloud CLI 並完成 gcloud auth login
#   2. 已設定 PROJECT_ID（見下方變數區）
#   3. 執行者帳號具備 roles/owner 或對應的細粒度 roles
# =============================================================================

set -euo pipefail

# ── 顏色輸出 ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# ── 參數驗證 ──────────────────────────────────────────────────────────────────
ENV="${1:-}"
[[ "$ENV" =~ ^(dev|staging|production)$ ]] || \
  err "請指定環境：./bootstrap.sh [dev|staging|production]"

# ── 專案設定（請依實際填入）──────────────────────────────────────────────────
PROJECT_ID="ots-translation"          # GCP Project ID
REGION="asia-east1"                   # 台灣 region
DB_ROOT_PASSWORD_FILE="$HOME/.ots-db-root-pw"  # 暫存 root 密碼檔路徑

# ── 命名規則（所有資源只差 env suffix）──────────────────────────────────────
# Cloud SQL
SQL_INSTANCE="ots-db-${ENV}"
SQL_DATABASE="ots"
SQL_APP_USER="ots_app"

# Cloud Storage buckets
# bucket 名稱加入 PROJECT_ID 確保 GCS 全球唯一
BUCKET_UPLOADS="${PROJECT_ID}-uploads-${ENV}"
BUCKET_OUTPUTS="${PROJECT_ID}-outputs-${ENV}"
BUCKET_TEMP="${PROJECT_ID}-pipeline-temp-${ENV}"

# BigQuery
BQ_DATASET="ots_corpus_${ENV}"

# Secret Manager
SECRET_DB_PASSWORD="ots-db-password-${ENV}"
SECRET_DB_URL="ots-db-url-${ENV}"

# Service Account
SA_NAME="ots-api-backend-${ENV}"
SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Pipeline SA（Cloud Run Jobs 用）
SA_PIPELINE_NAME="ots-pipeline-${ENV}"
SA_PIPELINE_EMAIL="${SA_PIPELINE_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# ── 確認設定 ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}=====================================================${NC}"
echo -e "${CYAN}  OTS Data Layer Bootstrap — ENV: ${YELLOW}${ENV}${NC}"
echo -e "${CYAN}=====================================================${NC}"
echo ""
echo "  Project    : $PROJECT_ID"
echo "  Region     : $REGION"
echo "  SQL        : $SQL_INSTANCE / db=$SQL_DATABASE / user=$SQL_APP_USER"
echo "  Buckets    : $BUCKET_UPLOADS, $BUCKET_OUTPUTS, $BUCKET_TEMP"
echo "  BigQuery   : $BQ_DATASET"
echo "  Secrets    : $SECRET_DB_PASSWORD, $SECRET_DB_URL"
echo "  SA API     : $SA_EMAIL"
echo "  SA Pipeline: $SA_PIPELINE_EMAIL"
echo ""

if [[ "$ENV" == "production" ]]; then
  warn "即將建立 PRODUCTION 環境資源，確認後按 Enter 繼續，Ctrl+C 取消..."
  read -r
fi

# ── 設定 gcloud 預設專案 ──────────────────────────────────────────────────────
log "設定 gcloud 預設專案..."
gcloud config set project "$PROJECT_ID"
ok "Project 設定完成：$PROJECT_ID"

# ── 啟用必要 API ──────────────────────────────────────────────────────────────
log "啟用必要 GCP APIs..."
gcloud services enable \
  sqladmin.googleapis.com \
  storage.googleapis.com \
  bigquery.googleapis.com \
  firestore.googleapis.com \
  secretmanager.googleapis.com \
  servicenetworking.googleapis.com \
  compute.googleapis.com \
  run.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  aiplatform.googleapis.com \
  --quiet
ok "APIs 啟用完成"

# =============================================================================
# 1. SERVICE ACCOUNTS
# =============================================================================
log "建立 Service Accounts..."

create_sa() {
  local name="$1" display="$2" desc="$3"
  if gcloud iam service-accounts describe "${name}@${PROJECT_ID}.iam.gserviceaccount.com" \
       --quiet &>/dev/null; then
    warn "SA 已存在，跳過：${name}"
  else
    gcloud iam service-accounts create "$name" \
      --display-name="$display" \
      --description="$desc" \
      --quiet
    ok "SA 建立完成：${name}"
  fi
}

create_sa "$SA_NAME" \
  "OTS API Backend [${ENV}]" \
  "API Backend Cloud Run service account - ${ENV}"

create_sa "$SA_PIPELINE_NAME" \
  "OTS Pipeline [${ENV}]" \
  "Translation pipeline Cloud Run Jobs service account - ${ENV}"

# API Backend SA roles
for role in \
  "roles/cloudsql.client" \
  "roles/secretmanager.secretAccessor" \
  "roles/storage.objectAdmin"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_EMAIL}" \
    --role="$role" \
    --condition=None \
    --quiet
done
ok "API Backend SA roles 授予完成"

# API Backend SA 自我授權（GCS Signed URL IAM 簽名用）
log "授予 API Backend SA 自我簽名權限..."
gcloud iam service-accounts add-iam-policy-binding "${SA_EMAIL}" \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/iam.serviceAccountTokenCreator" \
  --project="$PROJECT_ID" \
  --quiet
ok "Signed URL 簽名權限設定完成"

# Pipeline SA roles
for role in \
  "roles/cloudsql.client" \
  "roles/storage.objectAdmin" \
  "roles/bigquery.dataEditor" \
  "roles/bigquery.jobUser" \
  "roles/datastore.user" \
  "roles/secretmanager.secretAccessor"; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member="serviceAccount:${SA_PIPELINE_EMAIL}" \
    --role="$role" \
    --condition=None \
    --quiet
done
ok "Pipeline SA roles 授予完成"

# =============================================================================
# 2. CLOUD SQL
# =============================================================================
# =============================================================================
# 2a. PRIVATE SERVICE NETWORKING（Cloud SQL private IP 前置設定）
# =============================================================================
log "設定 Private Service Networking..."

# 啟用 Service Networking API
gcloud services enable servicenetworking.googleapis.com --quiet
ok "servicenetworking.googleapis.com 已啟用"

# 配置 Private Services IP 範圍（若已存在則跳過）
if gcloud compute addresses describe google-managed-services-default \
     --global --quiet &>/dev/null; then
  warn "IP 範圍已存在，跳過：google-managed-services-default"
else
  log "配置 Private Services IP 範圍..."
  gcloud compute addresses create google-managed-services-default \
    --global \
    --purpose=VPC_PEERING \
    --prefix-length=16 \
    --network=default \
    --quiet
  ok "IP 範圍配置完成"
fi

# 建立 VPC Peering（若已存在則跳過）
if gcloud services vpc-peerings list \
     --network=default \
     --project="$PROJECT_ID" \
     --quiet 2>/dev/null | grep -q "servicenetworking"; then
  warn "VPC Peering 已存在，跳過"
else
  log "建立 VPC Peering..."
  gcloud services vpc-peerings connect \
    --service=servicenetworking.googleapis.com \
    --ranges=google-managed-services-default \
    --network=default \
    --project="$PROJECT_ID" \
    --quiet
  ok "VPC Peering 建立完成（需等待 1–2 分鐘生效）"
  sleep 60
fi

# =============================================================================
# 2. CLOUD SQL
# =============================================================================
log "建立 Cloud SQL instance：$SQL_INSTANCE ..."

if gcloud sql instances describe "$SQL_INSTANCE" --quiet &>/dev/null; then
  warn "Cloud SQL instance 已存在，跳過建立：$SQL_INSTANCE"
else
  # 依環境選擇機器規格（三個環境均不開 public IP）
  if [[ "$ENV" == "production" ]]; then
    TIER="db-g1-small"
    AVAILABILITY="REGIONAL"
  elif [[ "$ENV" == "staging" ]]; then
    TIER="db-f1-micro"
    AVAILABILITY="ZONAL"
  else
    TIER="db-f1-micro"
    AVAILABILITY="ZONAL"
  fi

  gcloud sql instances create "$SQL_INSTANCE" \
    --database-version="POSTGRES_17" \
    --tier="$TIER" \
    --region="$REGION" \
    --availability-type="$AVAILABILITY" \
    --no-assign-ip \
    --network="projects/${PROJECT_ID}/global/networks/default" \
    --storage-type="SSD" \
    --storage-size="10GB" \
    --storage-auto-increase \
    --backup-start-time="02:00" \
    --retained-backups-count=7 \
    --enable-point-in-time-recovery \
    --quiet
  ok "Cloud SQL instance 建立完成：$SQL_INSTANCE ($TIER)"
fi

# 建立 database
if gcloud sql databases describe "$SQL_DATABASE" \
     --instance="$SQL_INSTANCE" --quiet &>/dev/null; then
  warn "Database 已存在，跳過：$SQL_DATABASE"
else
  gcloud sql databases create "$SQL_DATABASE" \
    --instance="$SQL_INSTANCE" \
    --charset="UTF8" \
    --quiet
  ok "Database 建立完成：$SQL_DATABASE"
fi

# 產生 app user 密碼
DB_APP_PASSWORD=$(openssl rand -base64 32 | tr -d '=/+' | cut -c1-32)

if gcloud sql users describe "$SQL_APP_USER" \
     --instance="$SQL_INSTANCE" --quiet &>/dev/null; then
  warn "DB user 已存在，重置密碼以確保與 Secret Manager 同步..."
  gcloud sql users set-password "$SQL_APP_USER" \
    --instance="$SQL_INSTANCE" \
    --password="$DB_APP_PASSWORD" \
    --quiet
  ok "DB user 密碼已重置：$SQL_APP_USER"
else
  gcloud sql users create "$SQL_APP_USER" \
    --instance="$SQL_INSTANCE" \
    --password="$DB_APP_PASSWORD" \
    --quiet
  ok "DB user 建立完成：$SQL_APP_USER"
fi

# =============================================================================
# 3. SECRET MANAGER
# =============================================================================
log "設定 Secret Manager..."

SQL_INSTANCE_CONNECTION="${PROJECT_ID}:${REGION}:${SQL_INSTANCE}"
DB_URL="postgresql+asyncpg://${SQL_APP_USER}:${DB_APP_PASSWORD}@/${SQL_DATABASE}?host=/cloudsql/${SQL_INSTANCE_CONNECTION}"

create_or_update_secret() {
  local name="$1" value="$2"
  if gcloud secrets describe "$name" --quiet &>/dev/null; then
    # 已存在：加一個新版本
    echo -n "$value" | gcloud secrets versions add "$name" --data-file=- --quiet
    warn "Secret 已存在，已新增版本：$name"
  else
    echo -n "$value" | gcloud secrets create "$name" \
      --data-file=- \
      --replication-policy="user-managed" \
      --locations="$REGION" \
      --quiet
    ok "Secret 建立完成：$name"
  fi
}

create_or_update_secret "$SECRET_DB_PASSWORD" "$DB_APP_PASSWORD"
create_or_update_secret "$SECRET_DB_URL"      "$DB_URL"

# 授予 SA 讀取 secret 的權限
for secret in "$SECRET_DB_PASSWORD" "$SECRET_DB_URL"; do
  for sa_email in "$SA_EMAIL" "$SA_PIPELINE_EMAIL"; do
    gcloud secrets add-iam-policy-binding "$secret" \
      --member="serviceAccount:${sa_email}" \
      --role="roles/secretmanager.secretAccessor" \
      --quiet
  done
done
ok "Secret Manager 設定完成"

# 把密碼記到本機安全位置（僅供管理員備查）
echo "$DB_APP_PASSWORD" > "${DB_ROOT_PASSWORD_FILE}-${ENV}"
chmod 600 "${DB_ROOT_PASSWORD_FILE}-${ENV}"
warn "DB app user 密碼已暫存至：${DB_ROOT_PASSWORD_FILE}-${ENV}（請妥善保管）"

# =============================================================================
# 4. CLOUD STORAGE BUCKETS
# =============================================================================
log "建立 Cloud Storage buckets..."

create_bucket() {
  local bucket="$1" lifecycle_file="$2"
  if gsutil ls -b "gs://${bucket}" &>/dev/null; then
    warn "Bucket 已存在，跳過：$bucket"
  else
    gsutil mb -l "$REGION" -b on "gs://${bucket}"
    # 關閉 public access
    gsutil pap set enforced "gs://${bucket}"
    ok "Bucket 建立完成：$bucket"
  fi
  # 套用 lifecycle policy
  if [[ -f "$lifecycle_file" ]]; then
    gsutil lifecycle set "$lifecycle_file" "gs://${bucket}"
    ok "Lifecycle policy 套用完成：$bucket"
  fi
}

create_bucket "$BUCKET_UPLOADS" "lifecycle/uploads-lifecycle.json"
create_bucket "$BUCKET_OUTPUTS" "lifecycle/outputs-lifecycle.json"
create_bucket "$BUCKET_TEMP"    "lifecycle/temp-lifecycle.json"

# 授予 SA 存取權限
gsutil iam ch \
  "serviceAccount:${SA_EMAIL}:roles/storage.objectViewer" \
  "gs://${BUCKET_UPLOADS}"

for bucket in "$BUCKET_UPLOADS" "$BUCKET_OUTPUTS" "$BUCKET_TEMP"; do
  gsutil iam ch \
    "serviceAccount:${SA_PIPELINE_EMAIL}:roles/storage.objectAdmin" \
    "gs://${bucket}"
done
ok "Storage IAM 設定完成"

# =============================================================================
# 5. FIRESTORE
# =============================================================================
log "設定 Firestore（Native mode）..."

# Firestore 每個 project 只有一個 database，不用 env suffix
# 但可用不同 collection prefix 區分環境（已在 app 層處理）
if gcloud firestore databases describe --quiet &>/dev/null; then
  warn "Firestore 已啟用，跳過建立"
else
  gcloud firestore databases create \
    --location="$REGION" \
    --type="firestore-native" \
    --quiet
  ok "Firestore 建立完成（Native mode, $REGION）"
fi

# =============================================================================
# 6. BIGQUERY
# =============================================================================
log "建立 BigQuery dataset：$BQ_DATASET ..."

if bq show --dataset "${PROJECT_ID}:${BQ_DATASET}" &>/dev/null; then
  warn "BigQuery dataset 已存在，跳過：$BQ_DATASET"
else
  bq mk \
    --dataset \
    --location="$REGION" \
    --description="OTS corpus parallel pairs - ${ENV}" \
    "${PROJECT_ID}:${BQ_DATASET}"
  ok "BigQuery dataset 建立完成：$BQ_DATASET"
fi

# 建立 corpus_pairs table（含 partition）
bq mk \
  --table \
  --time_partitioning_field="created_at" \
  --time_partitioning_type="MONTH" \
  --schema="schema/corpus_pairs_schema.json" \
  "${PROJECT_ID}:${BQ_DATASET}.corpus_pairs" \
  2>/dev/null && ok "Table 建立完成：corpus_pairs" \
  || warn "corpus_pairs table 已存在，跳過"

# 授予 Pipeline SA 存取權限
bq add-iam-policy-binding \
  --member="serviceAccount:${SA_PIPELINE_EMAIL}" \
  --role="roles/bigquery.dataEditor" \
  "${PROJECT_ID}:${BQ_DATASET}" \
  --quiet 2>/dev/null || true
ok "BigQuery IAM 設定完成"

# =============================================================================
# 完成摘要
# =============================================================================
echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  Bootstrap 完成 — ENV: ${YELLOW}${ENV}${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo "  Cloud SQL    : $SQL_INSTANCE (postgres15, no-public-ip)"
echo "  Buckets      : $BUCKET_UPLOADS / $BUCKET_OUTPUTS / $BUCKET_TEMP"
echo "  Firestore    : Native mode, $REGION"
echo "  BigQuery     : $BQ_DATASET.corpus_pairs (partitioned by month)"
echo "  Secrets      : $SECRET_DB_PASSWORD / $SECRET_DB_URL"
echo "  SA API       : $SA_EMAIL"
echo "  SA Pipeline  : $SA_PIPELINE_EMAIL"
echo ""
echo -e "${YELLOW}  後續手動步驟（需要 Cloud SQL superuser 連線執行）：${NC}"
echo "  請執行 ./init-db.sh $ENV 完成 DB schema 初始化"
echo ""
