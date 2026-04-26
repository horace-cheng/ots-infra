#!/usr/bin/env bash
# =============================================================================
# OTS — End-to-End Fast Track 測試腳本
# =============================================================================
# 流程：取得 Service URL → Firebase 登入取 Token → 建立訂單
#       → 取得上傳 URL → 上傳測試文本 → 確認上傳 → 管理員確認付款
#
# 前置條件：
#   1. Firebase 已建立測試用戶（一般用戶 + admin 用戶）
#   2. admin 用戶已在 admin_users 表建立記錄（./add_admin.sh）
#   3. ots-api-backend-dev 已部署
#
# 使用方式：
#   ENV=dev ./test_e2e.sh
#   或設定環境變數後直接執行：./test_e2e.sh
# =============================================================================

set -euo pipefail

# ── 顏色 ──────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()     { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()      { echo -e "${GREEN}✓${NC} $*"; }
warn()    { echo -e "${YELLOW}⚠${NC}  $*"; }
err()     { echo -e "${RED}✗ ERROR:${NC} $*" >&2; exit 1; }
section() { echo ""; echo -e "${BOLD}${CYAN}══ $* ══${NC}"; }

# ── 設定（可透過環境變數覆寫）────────────────────────────────────────────────
ENV="${ENV:-dev}"
PROJECT_ID="${PROJECT_ID:-ots-translation}"
REGION="${REGION:-asia-east1}"

# Firebase 設定（必填）
FIREBASE_API_KEY="${FIREBASE_API_KEY:-}"
USER_EMAIL="${USER_EMAIL:-}"
USER_PASSWORD="${USER_PASSWORD:-}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-}"

# 測試用台語文本
TEST_TEXT="${TEST_TEXT:-}"

# ── 前置檢查 ──────────────────────────────────────────────────────────────────
check_deps() {
  for cmd in curl python3 gcloud; do
    command -v "$cmd" &>/dev/null || err "缺少必要工具：$cmd"
  done
}

check_config() {
  [[ -n "$FIREBASE_API_KEY" ]] || err "請設定 FIREBASE_API_KEY 環境變數"
  [[ -n "$USER_EMAIL" ]]       || err "請設定 USER_EMAIL 環境變數"
  [[ -n "$USER_PASSWORD" ]]    || err "請設定 USER_PASSWORD 環境變數"
  [[ -n "$ADMIN_EMAIL" ]]      || err "請設定 ADMIN_EMAIL 環境變數"
  [[ -n "$ADMIN_PASSWORD" ]]   || err "請設定 ADMIN_PASSWORD 環境變數"
}

# ── 工具函式 ──────────────────────────────────────────────────────────────────
firebase_login() {
  local email="$1" password="$2"
  local response token

  response=$(curl -sf -X POST \
    "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{\"email\":\"${email}\",\"password\":\"${password}\",\"returnSecureToken\":true}" \
    2>&1) || err "Firebase 登入失敗（${email}）：${response}"

  token=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['idToken'])" 2>&1) \
    || err "無法解析 Firebase token：${response}"

  echo "$token"
}

api_call() {
  local method="$1" path="$2" token="$3"
  shift 3
  local body="${1:-}"
  local url="${SERVICE_URL}${path}"

  local args=(-sf -X "$method" "$url" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/json")

  [[ -n "$body" ]] && args+=(-d "$body")

  curl "${args[@]}" 2>&1
}

json_get() {
  local json="$1" key="$2"
  echo "$json" | python3 -c "import sys,json; print(json.load(sys.stdin)['${key}'])" 2>/dev/null
}

# ── 測試文本 ──────────────────────────────────────────────────────────────────
default_test_text() {
  cat << 'EOF'
阮是台灣人，佇遮生、佇遮大。
這塊土地，是阮的根、阮的夢。
山頂的雲，溪裡的水，攏是阮的記持。
阮愛這个所在，永遠袂放袂記。

田庄的早起，鳥仔咧唱歌，
風吹過稻田，芬芳滿四界。
阿媽的灶跤，飯香四散去，
彼段歲月，永遠揣袂著。
EOF
}

# =============================================================================
# MAIN
# =============================================================================
check_deps

echo ""
echo -e "${BOLD}OTS Fast Track — End-to-End Test${NC}"
echo -e "環境：${YELLOW}${ENV}${NC}  |  Project：${PROJECT_ID}"
echo ""

check_config

# 設定預設測試文本
[[ -z "$TEST_TEXT" ]] && TEST_TEXT=$(default_test_text)

# ── Step 1: 取得 Service URL ──────────────────────────────────────────────────
section "Step 1: 取得 Service URL"

SERVICE_NAME="ots-api-backend-${ENV}"
log "查詢 Cloud Run service：${SERVICE_NAME}..."

SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --region="$REGION" \
  --project="$PROJECT_ID" \
  --format="value(status.url)" 2>/dev/null || echo "")

[[ -n "$SERVICE_URL" ]] || err "找不到 Cloud Run service：${SERVICE_NAME}"
ok "Service URL：${SERVICE_URL}"

# Health check
log "Health check..."
HEALTH=$(curl -sf "${SERVICE_URL}/health" 2>&1) || err "Health check 失敗：${HEALTH}"
DB_STATUS=$(json_get "$HEALTH" "db")
[[ "$DB_STATUS" == "connected" ]] || warn "DB 狀態：${DB_STATUS}（非 connected）"
ok "Health check OK — DB: ${DB_STATUS}"

# ── Step 2: Firebase 登入 ──────────────────────────────────────────────────────
section "Step 2: Firebase 登入"

log "一般用戶登入：${USER_EMAIL}..."
USER_TOKEN=$(firebase_login "$USER_EMAIL" "$USER_PASSWORD")
ok "一般用戶 token 取得成功（${USER_TOKEN:0:20}...）"

log "Admin 用戶登入：${ADMIN_EMAIL}..."
ADMIN_TOKEN=$(firebase_login "$ADMIN_EMAIL" "$ADMIN_PASSWORD")
ok "Admin token 取得成功（${ADMIN_TOKEN:0:20}...）"

# ── Step 3: 建立訂單 ──────────────────────────────────────────────────────────
section "Step 3: 建立訂單"

ORDER_BODY='{
  "track_type":  "fast",
  "source_lang": "tai-lo",
  "target_lang": "en",
  "word_count":  200,
  "notes":       "E2E 自動測試訂單"
}'

log "POST /orders..."
ORDER_RESP=$(api_call POST /orders "$USER_TOKEN" "$ORDER_BODY")
echo "回應：$ORDER_RESP" | python3 -m json.tool 2>/dev/null || echo "$ORDER_RESP"

ORDER_ID=$(json_get "$ORDER_RESP" "order_id")
PRICE=$(json_get "$ORDER_RESP" "price_ntd")
PAYMENT_URL=$(json_get "$ORDER_RESP" "payment_url")

[[ -n "$ORDER_ID" ]] || err "建立訂單失敗：${ORDER_RESP}"
ok "訂單建立成功"
echo "  Order ID:    ${ORDER_ID}"
echo "  Price:       NT\$${PRICE}"
echo "  Payment URL: ${PAYMENT_URL}"

# ── Step 4: 取得上傳 URL ──────────────────────────────────────────────────────
section "Step 4: 取得上傳 Signed URL"

UPLOAD_BODY="{
  \"order_id\":     \"${ORDER_ID}\",
  \"filename\":     \"test_tailo.txt\",
  \"content_type\": \"text/plain\"
}"

log "POST /files/upload-url..."
UPLOAD_RESP=$(api_call POST /files/upload-url "$USER_TOKEN" "$UPLOAD_BODY")
echo "回應：$UPLOAD_RESP" | python3 -m json.tool 2>/dev/null || echo "$UPLOAD_RESP"

SIGNED_URL=$(json_get "$UPLOAD_RESP" "signed_url")
GCS_PATH=$(json_get "$UPLOAD_RESP" "gcs_path")

[[ -n "$SIGNED_URL" ]] || err "取得 Signed URL 失敗：${UPLOAD_RESP}"
ok "Signed URL 取得成功"
echo "  GCS Path: ${GCS_PATH}"

# ── Step 5: 上傳文本到 GCS ────────────────────────────────────────────────────
section "Step 5: 上傳測試台語文本"

log "PUT 文本到 GCS Signed URL..."
UPLOAD_STATUS=$(curl -sf -X PUT "$SIGNED_URL" \
  -H "Content-Type: text/plain" \
  --data-binary "$TEST_TEXT" \
  -o /dev/null -w "%{http_code}" 2>&1)

[[ "$UPLOAD_STATUS" == "200" ]] || err "GCS 上傳失敗（HTTP ${UPLOAD_STATUS}）"
ok "文本上傳成功（$(echo "$TEST_TEXT" | wc -c) bytes）"

# ── Step 6: 確認上傳 ──────────────────────────────────────────────────────────
section "Step 6: 通知 API 上傳完成"

log "POST /files/${ORDER_ID}/confirm..."
CONFIRM_RESP=$(curl -sf -X POST \
  "${SERVICE_URL}/files/${ORDER_ID}/confirm?gcs_path=${GCS_PATH}" \
  -H "Authorization: Bearer ${USER_TOKEN}" \
  -H "Content-Type: application/json" \
  2>&1)
ok "上傳確認完成：${CONFIRM_RESP}"

# ── Step 7: 查看訂單狀態（付款前）────────────────────────────────────────────
section "Step 7: 確認訂單狀態（付款前）"

log "GET /orders/${ORDER_ID}..."
ORDER_STATUS=$(api_call GET "/orders/${ORDER_ID}" "$USER_TOKEN")
STATUS=$(json_get "$ORDER_STATUS" "status")
PAYMENT_STATUS=$(json_get "$ORDER_STATUS" "payment_status")
ok "訂單狀態：status=${STATUS}，payment=${PAYMENT_STATUS}"

# ── Step 8: Admin 確認付款 ────────────────────────────────────────────────────
section "Step 8: Admin 確認付款（手動匯款模式）"

CONFIRM_BODY="{
  \"confirmed_amount_ntd\": ${PRICE},
  \"note\": \"E2E 測試自動確認\"
}"

log "POST /admin/payments/${ORDER_ID}/confirm..."
PAY_RESP=$(api_call POST "/admin/payments/${ORDER_ID}/confirm" "$ADMIN_TOKEN" "$CONFIRM_BODY")
echo "回應：${PAY_RESP}"
ok "付款確認完成"

# ── Step 9: 查看最終訂單狀態 ──────────────────────────────────────────────────
section "Step 9: 確認 Pipeline 已觸發"

log "等待 5 秒讓 Pub/Sub 傳遞..."
sleep 5

log "GET /orders/${ORDER_ID}..."
FINAL_ORDER=$(api_call GET "/orders/${ORDER_ID}" "$USER_TOKEN")
FINAL_STATUS=$(json_get "$FINAL_ORDER" "status")
ok "最終訂單狀態：${FINAL_STATUS}"

log "查看 Cloud Workflows 執行狀態..."
EXEC_LIST=$(gcloud workflows executions list "ots-pipeline-router-${ENV}" \
  --location="$REGION" \
  --project="$PROJECT_ID" \
  --limit=3 \
  --format="table(name.basename(), state, startTime)" 2>/dev/null || echo "（查詢失敗）")
echo "$EXEC_LIST"

# ── 摘要 ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}══ 測試完成 ══${NC}"
echo ""
echo "  Order ID:      ${ORDER_ID}"
echo "  Price:         NT\$${PRICE}"
echo "  Final Status:  ${FINAL_STATUS}"
echo "  GCS Upload:    ${GCS_PATH}"
echo ""
echo -e "${CYAN}後續追蹤：${NC}"
echo "  # 查看 Fast Track Workflow 狀態"
echo "  gcloud workflows executions list ots-fast-track-${ENV} \\"
echo "    --location=${REGION} --project=${PROJECT_ID} --limit=5"
echo ""
echo "  # 查看 QA Flags"
echo "  curl -s ${SERVICE_URL}/admin/qa-flags?order_id=${ORDER_ID} \\"
echo "    -H \"Authorization: Bearer \${ADMIN_TOKEN}\" | python3 -m json.tool"
echo ""
