-- 019: Add gcs_plain_text_output_path column for pure-text delivery
ALTER TABLE orders ADD COLUMN gcs_plain_text_output_path TEXT;
