-- Migration 025: Add Gutenberg track job types to job_type enum
-- Description: Allow the pipeline_jobs table to record Gutenberg pipeline
--              stages. The gt_process_chunk job runs once per mode
--              (translate / simplify / tailo) so the job_type column
--              gets three distinct enum values, one per mode.

ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'gt_fetcher';
ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'gt_extract_terms';
ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'gt_process_chunk_translate';
ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'gt_process_chunk_simplify';
ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'gt_process_chunk_tailo';
ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'gt_deliver';
