-- Migration 010: Fix literary_assignments FK to reference users instead of editors
-- Description: literary_assignments.editor_id and proofreader_id should reference users(id),
--              not editors(id). The admin UI assigns users, not legacy editor records.

BEGIN;

-- Drop existing FKs
ALTER TABLE literary_assignments DROP CONSTRAINT IF EXISTS literary_assignments_editor_id_fkey;
ALTER TABLE literary_assignments DROP CONSTRAINT IF EXISTS literary_assignments_proofreader_id_fkey;

-- Recreate FKs pointing to users(id)
ALTER TABLE literary_assignments
    ADD CONSTRAINT literary_assignments_editor_id_fkey FOREIGN KEY (editor_id) REFERENCES users(id),
    ADD CONSTRAINT literary_assignments_proofreader_id_fkey FOREIGN KEY (proofreader_id) REFERENCES users(id);

COMMIT;
