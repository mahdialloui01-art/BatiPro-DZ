CREATE TABLE IF NOT EXISTS sync_documents (
    organization_id UUID NOT NULL REFERENCES organizations(id),
    document_key TEXT NOT NULL,
    document_value TEXT,
    revision BIGINT NOT NULL DEFAULT 0 CHECK (revision >= 0),
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    updated_by_device TEXT NOT NULL,
    last_event_id BIGINT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (organization_id, document_key)
);

ALTER TABLE sync_documents ADD COLUMN IF NOT EXISTS last_event_id BIGINT NOT NULL DEFAULT 0;

CREATE TABLE IF NOT EXISTS sync_events (
    event_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    organization_id UUID NOT NULL REFERENCES organizations(id),
    document_key TEXT NOT NULL,
    document_value TEXT,
    revision BIGINT NOT NULL,
    is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
    device_id TEXT NOT NULL,
    mutation_id TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (organization_id, mutation_id)
);

CREATE INDEX IF NOT EXISTS idx_sync_events_org_event
    ON sync_events (organization_id, event_id);

CREATE TABLE IF NOT EXISTS sync_devices (
    organization_id UUID NOT NULL REFERENCES organizations(id),
    device_id TEXT NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_pulled_event_id BIGINT NOT NULL DEFAULT 0,
    PRIMARY KEY (organization_id, device_id)
);

INSERT INTO schema_migrations (version)
VALUES ('002_continuous_sync')
ON CONFLICT (version) DO NOTHING;
