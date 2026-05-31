-- Migration 022: Add LT QA checklist flag types
-- Description: Add 'missing_translation', 'segment_count_mismatch',
--              'number_inconsistency' to flag_type enum for lt_qa_checklist.

ALTER TYPE flag_type ADD VALUE IF NOT EXISTS 'missing_translation';
ALTER TYPE flag_type ADD VALUE IF NOT EXISTS 'segment_count_mismatch';
ALTER TYPE flag_type ADD VALUE IF NOT EXISTS 'number_inconsistency';
