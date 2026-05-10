-- Migration 015: Add revision_needed to order_status enum
-- Description: Allow orders table to reflect proofreader reject workflow

ALTER TYPE order_status ADD VALUE IF NOT EXISTS 'revision_needed';
