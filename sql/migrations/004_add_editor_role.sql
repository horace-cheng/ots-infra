-- Migration 004: Add Editor Role and Status
-- Description: Adds is_editor to users, editor_id to orders, and editor_verify to order_status enum.

BEGIN;

-- 1. Add is_editor to users table
ALTER TABLE users ADD COLUMN is_editor BOOLEAN NOT NULL DEFAULT FALSE;

-- 2. Add editor_id to orders table
ALTER TABLE orders ADD COLUMN editor_id UUID REFERENCES users(id);

-- 3. Add editor_verify to order_status enum
-- Note: PostgreSQL doesn't allow adding values to ENUMs inside a transaction block easily in some versions, 
-- but since we are using PostgreSQL 15, we can use ALTER TYPE ... ADD VALUE.
-- HOWEVER, it cannot be run in a multi-statement transaction in some environments.
-- We will run it outside if needed, but standard SQL migrations often use this.
ALTER TYPE order_status ADD VALUE 'editor_verify' AFTER 'qa_review';

COMMIT;
