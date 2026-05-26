-- 018: Add gcs_bilingual_output_path column for bilingual (side-by-side) delivery
ALTER TABLE orders ADD COLUMN gcs_bilingual_output_path TEXT;
