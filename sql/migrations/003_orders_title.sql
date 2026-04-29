-- Migration 003: add title column to orders table
ALTER TABLE orders ADD COLUMN IF NOT EXISTS title VARCHAR(100);
