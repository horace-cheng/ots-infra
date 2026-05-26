-- 017: Backfill assignment rows for orders missing them
-- Older orders (especially LT) created before the INSERT INTO assignments
-- was added to orders.py may not have an assignments row.
-- The API now auto-creates one on first assign, but the workflow's
-- internal GET /assignments/{id} endpoint still needs a row to exist.

INSERT INTO assignments (order_id, status, assigned_at)
SELECT id, 'pending', NOW()
FROM orders o
WHERE NOT EXISTS (SELECT 1 FROM assignments a WHERE a.order_id = o.id);
