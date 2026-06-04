-- Migration 023: Create translation_versions table
-- Description: Track version history of translation segments.
-- Each version is a full snapshot of translations.json stored in GCS.
-- Auto-saved at NMT completion, editor/proofreader complete, admin manual save.

CREATE TABLE translation_versions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id       UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  version        INTEGER NOT NULL,
  label          VARCHAR(200),
  created_by     UUID REFERENCES users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  gcs_path       TEXT NOT NULL,
  segment_count  INTEGER,
  source         VARCHAR(20) NOT NULL
    CHECK (source IN ('nmt','editor','proofreader','admin','pre_retranslate','manual','restored')),
  UNIQUE(order_id, version)
);

CREATE INDEX idx_translation_versions_order ON translation_versions(order_id, version DESC);
