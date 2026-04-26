-- =============================================================================
-- OTS Translation Service — Cloud SQL DDL
-- PostgreSQL 15
-- 執行方式：透過 init-db.sh 或 Cloud SQL Auth Proxy 直連
-- =============================================================================

BEGIN;

-- ── 清除既有資料表與 ENUM（CASCADE 處理所有依賴，IF EXISTS 避免首次報錯）
-- 先 DROP TABLE（有外鍵依賴需依序）
DROP TABLE IF EXISTS corpus_log          CASCADE;
DROP TABLE IF EXISTS literary_assignments CASCADE;
DROP TABLE IF EXISTS qa_flags            CASCADE;
DROP TABLE IF EXISTS pipeline_jobs       CASCADE;
DROP TABLE IF EXISTS payments            CASCADE;
DROP TABLE IF EXISTS orders              CASCADE;
DROP TABLE IF EXISTS editors             CASCADE;
DROP TABLE IF EXISTS admin_users         CASCADE;
DROP TABLE IF EXISTS users               CASCADE;

-- 再 DROP ENUM
DROP TYPE IF EXISTS assignment_status CASCADE;
DROP TYPE IF EXISTS flag_type         CASCADE;
DROP TYPE IF EXISTS flag_level        CASCADE;
DROP TYPE IF EXISTS job_status        CASCADE;
DROP TYPE IF EXISTS job_type          CASCADE;
DROP TYPE IF EXISTS invoice_status    CASCADE;
DROP TYPE IF EXISTS invoice_type      CASCADE;
DROP TYPE IF EXISTS payment_status    CASCADE;
DROP TYPE IF EXISTS payment_method    CASCADE;
DROP TYPE IF EXISTS lang_code         CASCADE;
DROP TYPE IF EXISTS order_status      CASCADE;
DROP TYPE IF EXISTS track_type        CASCADE;

-- ── ENUM 型別 ──────────────────────────────────────────────────────────────

CREATE TYPE track_type AS ENUM ('fast', 'literary');

CREATE TYPE order_status AS ENUM (
    'pending_payment', 'paid', 'processing',
    'qa_review', 'delivered', 'cancelled'
);

CREATE TYPE lang_code AS ENUM (
    'tai-lo', 'hakka', 'indigenous', 'zh-tw', 'en', 'ja', 'ko'
);

CREATE TYPE payment_method AS ENUM (
    'credit_card', 'atm', 'cvs', 'wire_transfer'
);

CREATE TYPE payment_status AS ENUM (
    'pending', 'paid', 'refunded', 'failed'
);

CREATE TYPE invoice_type AS ENUM (
    'b2c_cloud', 'b2b_triplicate'
);

CREATE TYPE invoice_status AS ENUM ('pending', 'issued', 'void');

CREATE TYPE job_type AS ENUM (
    'preprocess', 'nmt_stage1', 'nmt_stage2',
    'qa_auto', 'qa_human', 'format_deliver'
);

CREATE TYPE job_status AS ENUM (
    'queued', 'running', 'success', 'failed', 'skipped'
);

CREATE TYPE flag_level AS ENUM ('must_fix', 'review', 'pass');

CREATE TYPE flag_type AS ENUM (
    'length_ratio', 'missing_segment', 'semantic_drift',
    'terminology_mismatch', 'readability_low'
);

CREATE TYPE assignment_status AS ENUM (
    'pending', 'editing', 'editor_done',
    'proofreading', 'proofread_done', 'delivered'
);

-- ── 資料表 ────────────────────────────────────────────────────────────────

CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    uid_firebase    VARCHAR(128) UNIQUE NOT NULL,
    client_type     VARCHAR(10)  NOT NULL CHECK (client_type IN ('b2c','b2b')),
    company_name    VARCHAR(200),
    tax_id          VARCHAR(20),
    invoice_carrier VARCHAR(50),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID         NOT NULL REFERENCES users(id),
    track_type      track_type   NOT NULL,
    status          order_status NOT NULL DEFAULT 'pending_payment',
    source_lang     lang_code    NOT NULL,
    target_lang     lang_code    NOT NULL,
    word_count      INT          NOT NULL CHECK (word_count > 0),
    price_ntd       INT          NOT NULL CHECK (price_ntd > 0),
    gcs_upload_path TEXT,
    gcs_output_path TEXT,
    term_dict_id    VARCHAR(128),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deadline_at     TIMESTAMPTZ,
    delivered_at    TIMESTAMPTZ
);

CREATE TABLE payments (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id           UUID           NOT NULL REFERENCES orders(id),
    ecpay_trade_no     VARCHAR(50)    UNIQUE,
    payment_method     payment_method,
    payment_status     payment_status NOT NULL DEFAULT 'pending',
    amount_ntd         INT            NOT NULL,
    paid_at            TIMESTAMPTZ,
    invoice_no         VARCHAR(20),
    invoice_type       invoice_type,
    invoice_status     invoice_status DEFAULT 'pending',
    invoice_issued_at  TIMESTAMPTZ,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE pipeline_jobs (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id         UUID       NOT NULL REFERENCES orders(id),
    job_type         job_type   NOT NULL,
    status           job_status NOT NULL DEFAULT 'queued',
    gcp_workflow_id  VARCHAR(255),
    qa_result        JSONB,
    retry_count      INT        NOT NULL DEFAULT 0,
    error_message    TEXT,
    started_at       TIMESTAMPTZ,
    finished_at      TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE qa_flags (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    job_id              UUID       NOT NULL REFERENCES pipeline_jobs(id),
    paragraph_index     INT        NOT NULL,
    flag_level          flag_level NOT NULL,
    flag_type           flag_type  NOT NULL,
    source_segment      TEXT,
    translated_segment  TEXT,
    reviewer_note       TEXT,
    resolved            BOOLEAN    NOT NULL DEFAULT FALSE,
    flagged_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    resolved_at         TIMESTAMPTZ
);

CREATE TABLE editors (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(100) NOT NULL,
    email           VARCHAR(255) UNIQUE NOT NULL,
    target_langs    lang_code[]  NOT NULL,
    specialization  TEXT,
    active          BOOLEAN      NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE literary_assignments (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id                UUID              NOT NULL UNIQUE REFERENCES orders(id),
    editor_id               UUID              REFERENCES editors(id),
    proofreader_id          UUID              REFERENCES editors(id),
    status                  assignment_status NOT NULL DEFAULT 'pending',
    assigned_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    editor_submitted_at     TIMESTAMPTZ,
    proofread_submitted_at  TIMESTAMPTZ
);

CREATE TABLE corpus_log (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id      UUID        NOT NULL UNIQUE REFERENCES orders(id),
    consent_given BOOLEAN     NOT NULL DEFAULT FALSE,
    bq_row_id     VARCHAR(255),
    logged_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE admin_users (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    uid_firebase VARCHAR(128) UNIQUE NOT NULL,
    email        VARCHAR(255) NOT NULL,
    role         VARCHAR(20)  NOT NULL DEFAULT 'admin'
                 CHECK (role IN ('admin', 'superadmin')),
    note         TEXT,
    active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Index ──────────────────────────────────────────────────────────────────

CREATE INDEX idx_orders_user_id   ON orders(user_id);
CREATE INDEX idx_orders_status    ON orders(status);
CREATE INDEX idx_orders_track     ON orders(track_type);

CREATE INDEX idx_pipeline_order   ON pipeline_jobs(order_id);
CREATE INDEX idx_pipeline_status  ON pipeline_jobs(status);

CREATE INDEX idx_qa_flags_job     ON qa_flags(job_id);
CREATE INDEX idx_qa_flags_level   ON qa_flags(flag_level);

-- ── Trigger: updated_at 自動維護 ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ── DB user 權限（ots_app 已由 bootstrap.sh 建立）────────────────────────

GRANT CONNECT ON DATABASE ots TO ots_app;
-- admin_users: ots_app 只能 SELECT / INSERT / UPDATE，不能 DELETE
GRANT SELECT, INSERT, UPDATE ON admin_users TO ots_app;
GRANT USAGE ON SCHEMA public TO ots_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ots_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ots_app;

COMMIT;
