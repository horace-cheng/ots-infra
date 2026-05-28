-- 020: Add token_usage table for tracking Gemini API token consumption and cost

CREATE TABLE token_usage (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id          UUID         NOT NULL REFERENCES orders(id),
    job_type          VARCHAR(50)  NOT NULL,
    model             VARCHAR(50)  NOT NULL,
    prompt_tokens     INT          NOT NULL,
    candidates_tokens INT          NOT NULL,
    total_tokens      INT          NOT NULL,
    cost_usd          NUMERIC(10,6) NOT NULL DEFAULT 0,
    created_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_token_usage_order_id ON token_usage(order_id);

COMMENT ON TABLE  token_usage IS 'Per-call Gemini API token usage and cost for cost tracking';
COMMENT ON COLUMN token_usage.job_type IS 'Pipeline job key, e.g. nmt, ft_qa_auto, lt_preprocess_nmt';
COMMENT ON COLUMN token_usage.model IS 'Model name, e.g. gemini-2.5-pro, gemini-2.5-flash';
COMMENT ON COLUMN token_usage.cost_usd IS 'Calculated cost in USD at the time of the API call';
