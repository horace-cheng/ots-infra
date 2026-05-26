CREATE TABLE language_configs (
    id               SERIAL PRIMARY KEY,
    code             VARCHAR(20)   NOT NULL,
    label_zh         VARCHAR(50)   NOT NULL,
    label_en         VARCHAR(50)   NOT NULL,
    direction        VARCHAR(10)   NOT NULL CHECK (direction IN ('source', 'target', 'both')),
    is_active        BOOLEAN       NOT NULL DEFAULT true,
    sort_order       INTEGER       NOT NULL DEFAULT 0,
    price_multiplier NUMERIC(4,2)  NOT NULL DEFAULT 1.0,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    UNIQUE (code, direction)
);

-- Seed with all currently hardcoded languages (active)
INSERT INTO language_configs (code, label_zh, label_en, direction, sort_order, price_multiplier) VALUES
    ('tai-lo',     '台語（台羅拼音）', 'Taiwanese (Tâi-lô)',   'source', 10, 1.0),
    ('hakka',      '客語',           'Hakka',                 'source', 20, 1.0),
    ('indigenous', '原住民族語',      'Indigenous Languages',  'source', 30, 1.0),
    ('zh-tw',      '繁體中文',        'Traditional Chinese',   'both',   40, 1.0),
    ('en',         '英語',           'English',               'target', 10, 1.0),
    ('ja',         '日語',           'Japanese',              'target', 20, 1.2),
    ('ko',         '韓語',           'Korean',                'target', 30, 1.0);
