-- 014: Sample Translation Package (試譯提案包)
--
-- Adds:
--   1. users.bio          — Editor translator bio for the package
--   2. orders.has_sample_package — Whether user opted into the package
--   3. order_sample_packages table — Stores package components 1,2,3,5

BEGIN;

ALTER TABLE users ADD COLUMN IF NOT EXISTS bio TEXT NOT NULL DEFAULT '';

ALTER TABLE orders ADD COLUMN IF NOT EXISTS has_sample_package BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS order_sample_packages (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
    status          TEXT NOT NULL DEFAULT 'draft',  -- draft → generated → completed

    -- Component 1: Translator's CV / Bio
    translator_bio  TEXT NOT NULL DEFAULT '',

    -- Component 2: Book Fact Sheet
    -- JSON with keys: title, author, publisher, pub_date, word_count, category, sales
    book_fact_sheet JSONB NOT NULL DEFAULT '{}',

    -- Component 3: Synopsis (500–800 words, Gemini-generated)
    synopsis        TEXT NOT NULL DEFAULT '',

    -- Component 5: Market Analysis
    market_analysis TEXT NOT NULL DEFAULT '',

    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by      UUID REFERENCES users(id)
);

COMMIT;
