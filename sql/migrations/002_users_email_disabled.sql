-- Migration 002: add email and disabled columns to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS email    VARCHAR(255);
ALTER TABLE users ADD COLUMN IF NOT EXISTS disabled BOOLEAN NOT NULL DEFAULT FALSE;
