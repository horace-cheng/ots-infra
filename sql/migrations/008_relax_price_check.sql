-- Migration 008: Allow price_ntd = 0 for Literary Track (awaiting quote)
-- LT orders start with price_ntd=0 until admin sets the quote.

BEGIN;

-- Drop existing check constraint (name may vary by DB creation script)
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_price_ntd_check;

-- Add new constraint: allow 0 for LT awaiting_quote, but require > 0 for paid/delivered
ALTER TABLE orders ADD CONSTRAINT orders_price_ntd_check
    CHECK (price_ntd >= 0);

COMMIT;
