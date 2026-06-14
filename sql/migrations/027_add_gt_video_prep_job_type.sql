-- Migration 027: Add gt_video_prep job type to job_type enum
-- Description: The 2026-06-12 gt_video_prep pipeline job was added for
--              automated storyboard and narration generation. This migration
--              adds the enum value so pipeline_jobs can track its status.
--
-- See also: gt_video_prep/main.py and deploy_pipeline.sh

ALTER TYPE job_type ADD VALUE IF NOT EXISTS 'gt_video_prep';
