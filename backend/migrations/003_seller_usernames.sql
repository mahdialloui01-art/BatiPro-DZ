ALTER TABLE users ADD COLUMN IF NOT EXISTS username TEXT;

UPDATE users
SET username = 'user_' || replace(left(id::text, 12), '-', '')
WHERE username IS NULL OR btrim(username) = '';

CREATE UNIQUE INDEX IF NOT EXISTS users_username_ci_unique
    ON users (lower(username))
    WHERE username IS NOT NULL;

CREATE INDEX IF NOT EXISTS organization_members_role_idx
    ON organization_members (organization_id, role);
