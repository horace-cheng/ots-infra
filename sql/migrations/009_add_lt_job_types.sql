-- Migration 009: Literary Track — Pipeline job types
-- Description: Adds LT-specific job_type enum values for pipeline jobs.

ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'lt_preprocess_nmt';
ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'lt_qa_checklist';
ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'lt_deliver';
