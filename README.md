# OTS Data Layer Infrastructure Scripts

GCP Data Layer 初始化腳本，支援 `dev` / `staging` / `production` 三個環境。

## 目錄結構

```
ots-infra/
├── bootstrap.sh              # 主要初始化腳本（SA、SQL、Storage、BQ、Secrets）
├── init-db.sh                # DB Schema 初始化（需 bootstrap 完成後執行）
├── sql/
│   └── schema.sql            # 完整 DDL（ENUM → 資料表 → Index → Trigger）
├── lifecycle/
│   ├── uploads-lifecycle.json   # 上傳檔案：30 天刪除
│   ├── outputs-lifecycle.json   # 輸出檔案：90 天轉 Coldline，180 天刪除
│   └── temp-lifecycle.json      # Pipeline 暫存：7 天刪除
└── schema/
    └── corpus_pairs_schema.json # BigQuery corpus_pairs table schema
```

## 命名規則

所有資源只差環境 suffix，其餘完全一致：

| 資源             | dev                    | staging                    | production                    |
|-----------------|------------------------|----------------------------|-------------------------------|
| Cloud SQL       | `ots-db-dev`           | `ots-db-staging`           | `ots-db-production`           |
| Bucket uploads  | `ots-uploads-dev`      | `ots-uploads-staging`      | `ots-uploads-production`      |
| Bucket outputs  | `ots-outputs-dev`      | `ots-outputs-staging`      | `ots-outputs-production`      |
| Bucket temp     | `ots-pipeline-temp-dev`| `ots-pipeline-temp-staging`| `ots-pipeline-temp-production`|
| BigQuery        | `ots_corpus_dev`       | `ots_corpus_staging`       | `ots_corpus_production`       |
| Secret DB pw    | `ots-db-password-dev`  | `ots-db-password-staging`  | `ots-db-password-production`  |
| SA API          | `ots-api-backend-dev`  | `ots-api-backend-staging`  | `ots-api-backend-production`  |
| SA Pipeline     | `ots-pipeline-dev`     | `ots-pipeline-staging`     | `ots-pipeline-production`     |

> Firestore 每個 Project 只有一個 database，以 collection prefix 區分環境（在 app 層處理）。

## 前置條件

```bash
# 1. 安裝 gcloud CLI
# https://cloud.google.com/sdk/docs/install

# 2. 登入
gcloud auth login
gcloud auth application-default login

# 3. 安裝 cloud-sql-proxy（init-db.sh 需要）
# https://cloud.google.com/sql/docs/postgres/sql-proxy

# 4. 確認 PROJECT_ID 已在 bootstrap.sh 中設定正確
```

## 使用方式

### Step 1：執行 bootstrap

```bash
chmod +x bootstrap.sh init-db.sh

# dev 環境
./bootstrap.sh dev

# staging 環境
./bootstrap.sh staging

# production 環境（會多一個確認提示）
./bootstrap.sh production
```

### Step 2：初始化 DB Schema

```bash
./init-db.sh dev
./init-db.sh staging
./init-db.sh production
```

## Cloud SQL 規格差異

| 環境        | Tier          | Availability | 備注               |
|------------|---------------|-------------|-------------------|
| dev        | db-f1-micro   | ZONAL       | 最低成本            |
| staging    | db-f1-micro   | ZONAL       | 與 dev 相同規格測試   |
| production | db-g1-small   | REGIONAL    | HA 雙區域備援        |

## 注意事項

- `bootstrap.sh` 使用 `set -euo pipefail`，任何步驟失敗即中止，可安全重複執行
- DB app user 密碼自動產生並存入 `~/.ots-db-root-pw-{env}`，請妥善保管
- Cloud SQL 設定 `--no-assign-ip`，不開放 Public IP
- Production 環境執行前會出現確認提示
