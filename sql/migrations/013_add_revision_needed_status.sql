-- Migration 013: Add revision_needed to assignment_status enum
-- Description: Support proofreader reject workflow (editor -> proofreader -> revision_needed loop)

ALTER TYPE assignment_status ADD VALUE IF NOT EXISTS 'revision_needed';
