-- Migration 026: Add gt_chapter_splitter and gt_split job types to job_type enum
-- Description: The 2026-06-07 gt_process_chunk split replaced the single
--              gt_process_chunk_* values with three jobs (gt_translate,
--              gt_simplify, gt_tailo) and added a new gt_chapter_splitter
--              job. This migration adds the missing enum values so the
--              pipeline_jobs table can record these new stages.
--
-- Background: 2026-06-07 split gt_process_chunk → 3 jobs (gt_translate,
--              gt_simplify, gt_tailo), so the old gt_process_chunk_*
--              values are obsolete. They're left in the enum for historical
--              pipeline_jobs rows.

ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'gt_chapter_splitter';
ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'gt_translate';
ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'gt_simplify';
ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'gt_tailo';
