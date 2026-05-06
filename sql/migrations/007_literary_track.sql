-- Migration 007: Literary Track — Quotation, Support Files, LT Enhancements
-- Description: Adds quotation flow for LT (awaiting_quote/quoted statuses, quoted_price),
--              support materials table, LT-specific timestamps/notes on literary_assignments.

-- ── 1. New order statuses for LT quotation flow ──────────────────────────────
-- These cannot run in a transaction in PostgreSQL, so keep them outside BEGIN/COMMIT.
ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'awaiting_quote';
ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'quoted';

BEGIN;


-- ── 2. Orders table: quotation columns ───────────────────────────────────────

ALTER TABLE orders ADD COLUMN IF NOT EXISTS quoted_price INT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS quoted_at TIMESTAMPTZ;

-- Auto-calculated reference price (word_count × rate), shown to admin only
ALTER TABLE orders ADD COLUMN IF NOT EXISTS reference_price INT;


-- ── 3. Support materials table ───────────────────────────────────────────────
-- LT users can upload multiple reference files (glossaries, style guides,
-- background docs, previous translations, etc.) in addition to the main source.
-- These are provided to the LLM as context for higher-quality translation.

CREATE TABLE IF NOT EXISTS order_support_files (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id     UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    filename     TEXT NOT NULL,
    content_type TEXT NOT NULL,
    file_size    BIGINT NOT NULL,
    gcs_path     TEXT NOT NULL,
    file_role    TEXT NOT NULL DEFAULT 'reference',
               -- reference | glossary | style_guide | background | other
    created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    uploaded_by  UUID NOT NULL REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_support_files_order ON order_support_files(order_id);


-- ── 4. Literary assignments: timestamp and notes columns ─────────────────────

ALTER TABLE literary_assignments ADD COLUMN IF NOT EXISTS editor_assigned_at TIMESTAMPTZ;
ALTER TABLE literary_assignments ADD COLUMN IF NOT EXISTS editor_completed_at TIMESTAMPTZ;
ALTER TABLE literary_assignments ADD COLUMN IF NOT EXISTS proofreader_assigned_at TIMESTAMPTZ;
ALTER TABLE literary_assignments ADD COLUMN IF NOT EXISTS proofreader_completed_at TIMESTAMPTZ;

ALTER TABLE literary_assignments ADD COLUMN IF NOT EXISTS editor_notes TEXT;
ALTER TABLE literary_assignments ADD COLUMN IF NOT EXISTS proofreader_notes TEXT;


-- ── 5. Orders: LT output paths ───────────────────────────────────────────────

ALTER TABLE orders ADD COLUMN IF NOT EXISTS gcs_editor_path TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS gcs_proofreader_path TEXT;


-- ── 6. Backfill: existing LT orders get reference_price = price_ntd ──────────

UPDATE orders
SET reference_price = price_ntd
WHERE track_type = 'literary'
  AND reference_price IS NULL
  AND price_ntd IS NOT NULL;


COMMIT;

-- =============================================================================
-- ROLLBACK (if needed):
-- =============================================================================
-- BEGIN;
-- ALTER TABLE orders DROP COLUMN IF EXISTS quoted_price;
-- ALTER TABLE orders DROP COLUMN IF EXISTS quoted_at;
-- ALTER TABLE orders DROP COLUMN IF EXISTS reference_price;
-- ALTER TABLE orders DROP COLUMN IF EXISTS gcs_editor_path;
-- ALTER TABLE orders DROP COLUMN IF EXISTS gcs_proofreader_path;
-- DROP TABLE IF EXISTS order_support_files CASCADE;
-- ALTER TABLE literary_assignments DROP COLUMN IF EXISTS editor_assigned_at;
-- ALTER TABLE literary_assignments DROP COLUMN IF EXISTS editor_completed_at;
-- ALTER TABLE literary_assignments DROP COLUMN IF EXISTS proofreader_assigned_at;
-- ALTER TABLE literary_assignments DROP COLUMN IF EXISTS proofreader_completed_at;
-- ALTER TABLE literary_assignments DROP COLUMN IF EXISTS editor_notes;
-- ALTER TABLE literary_assignments DROP COLUMN IF EXISTS proofreader_notes;
-- COMMIT;
