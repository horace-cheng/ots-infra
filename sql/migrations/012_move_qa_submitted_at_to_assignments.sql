-- 012_move_qa_submitted_at_to_assignments.sql
-- Move qa_submitted_at from orders to assignments table

-- Add column to assignments
ALTER TABLE assignments ADD COLUMN qa_submitted_at TIMESTAMPTZ;

-- Migrate data from orders to assignments
UPDATE assignments SET qa_submitted_at = o.qa_submitted_at
FROM orders o
WHERE assignments.order_id = o.id AND o.qa_submitted_at IS NOT NULL;

-- Drop from orders
ALTER TABLE orders DROP COLUMN qa_submitted_at;
