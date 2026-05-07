-- Migration 011: Unify assignments table
-- Description:
--   1. Rename literary_assignments → assignments (unified for FT + LT)
--   2. Add qa_id column (used by FT only)
--   3. Migrate existing FT data from orders.editor_id / orders.qa_id → assignments
--   4. Drop orders.editor_id / orders.qa_id columns

BEGIN;

-- ── 1. Rename literary_assignments → assignments ─────────────────────────────
ALTER TABLE literary_assignments RENAME TO assignments;

-- ── 2. Add qa_id column (for FT QA reviewer) ─────────────────────────────────
ALTER TABLE assignments ADD COLUMN qa_id UUID REFERENCES users(id);

-- ── 3. Create FT assignment rows from existing orders data ───────────────────
INSERT INTO assignments (order_id, editor_id, qa_id, status, assigned_at)
SELECT id, editor_id, qa_id, 'editing', NOW()
FROM orders
WHERE track_type = 'fast' AND (editor_id IS NOT NULL OR qa_id IS NOT NULL);

-- Also create pending assignments for all FT orders that don't have one yet
INSERT INTO assignments (order_id, status, assigned_at)
SELECT id, 'pending', NOW()
FROM orders o
WHERE track_type = 'fast'
  AND NOT EXISTS (SELECT 1 FROM assignments a WHERE a.order_id = o.id);

-- ── 4. Drop editor_id and qa_id from orders ──────────────────────────────────
ALTER TABLE orders DROP COLUMN IF EXISTS editor_id;
ALTER TABLE orders DROP COLUMN IF EXISTS qa_id;

COMMIT;

-- =============================================================================
-- ROLLBACK (if needed):
-- =============================================================================
-- BEGIN;
-- ALTER TABLE orders ADD COLUMN editor_id UUID REFERENCES users(id);
-- ALTER TABLE orders ADD COLUMN qa_id UUID REFERENCES users(id);
-- UPDATE orders o SET editor_id = (SELECT editor_id FROM assignments a WHERE a.order_id = o.id);
-- UPDATE orders o SET qa_id = (SELECT qa_id FROM assignments a WHERE a.order_id = o.id);
-- ALTER TABLE assignments DROP COLUMN qa_id;
-- ALTER TABLE assignments RENAME TO literary_assignments;
-- COMMIT;
