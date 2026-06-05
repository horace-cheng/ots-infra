-- Migration 024: Add 'gutenberg' to track_type enum
-- Description: Allow the orders table to record Gutenberg book translation jobs
--              (Project Gutenberg books translated via the Gutenberg track).

ALTER TYPE track_type ADD VALUE IF NOT EXISTS 'gutenberg';
