-- Migration 006: Add partial_untranslated flag_type
-- Description: Add 'untranslated' and 'partial_untranslated' to flag_type enum
--              for QA Layer 1 detection of lazy translations.

ALTER TYPE flag_type ADD VALUE IF NOT EXISTS 'untranslated';
ALTER TYPE flag_type ADD VALUE IF NOT EXISTS 'partial_untranslated';
