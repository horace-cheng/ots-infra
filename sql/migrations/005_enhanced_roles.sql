-- Migration 005: Enhanced Editor and QA Role System
-- Description: Adds user_roles and invitations tables, and qa_id to orders.

BEGIN;

-- 1. Create user_roles table
CREATE TABLE user_roles (
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role       VARCHAR(20) NOT NULL CHECK (role IN ('admin', 'editor', 'qa')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, role)
);

-- 2. Migrate existing roles
-- Migrate admin_users to user_roles
INSERT INTO user_roles (user_id, role, created_at)
SELECT u.id, 'admin', au.created_at
FROM admin_users au
JOIN users u ON u.uid_firebase = au.uid_firebase
WHERE au.active = true
ON CONFLICT DO NOTHING;

-- Migrate is_editor to user_roles
INSERT INTO user_roles (user_id, role)
SELECT id, 'editor'
FROM users
WHERE is_editor = true
ON CONFLICT DO NOTHING;

-- 3. Update orders table
ALTER TABLE orders ADD COLUMN qa_id UUID REFERENCES users(id);
ALTER TABLE orders ADD COLUMN qa_submitted_at TIMESTAMPTZ;

-- 4. Create invitations table
CREATE TABLE invitations (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    inviter_id  UUID NOT NULL REFERENCES users(id),
    email       VARCHAR(255) NOT NULL,
    role        VARCHAR(20) NOT NULL CHECK (role IN ('editor', 'qa')),
    token       VARCHAR(128) UNIQUE NOT NULL,
    status      VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'expired')),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at  TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days')
);

-- 5. Create user_languages table
CREATE TABLE user_languages (
    user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    source_lang VARCHAR(10) NOT NULL,
    target_lang VARCHAR(10) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, source_lang, target_lang)
);

COMMIT;
