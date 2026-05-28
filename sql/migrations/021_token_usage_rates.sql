-- 021: Add unit rates to token_usage for transparent cost calculation display

ALTER TABLE token_usage
  ADD COLUMN input_rate  NUMERIC(10,6) NOT NULL DEFAULT 0,
  ADD COLUMN output_rate NUMERIC(10,6) NOT NULL DEFAULT 0;

COMMENT ON COLUMN token_usage.input_rate  IS 'Per-1M-tokens input cost in USD at time of API call';
COMMENT ON COLUMN token_usage.output_rate IS 'Per-1M-tokens output cost in USD at time of API call';
