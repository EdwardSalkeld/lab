CREATE TABLE IF NOT EXISTS collector_state (
    id integer PRIMARY KEY CHECK (id = 1),
    initialized boolean NOT NULL DEFAULT false,
    last_success timestamptz
);
INSERT INTO collector_state(id) VALUES (1) ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS devices (
    mac text PRIMARY KEY,
    first_observed timestamptz NOT NULL,
    last_observed timestamptz NOT NULL,
    friendly_name text NOT NULL DEFAULT '',
    hostname text NOT NULL DEFAULT '',
    vendor text NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS observations (
    mac text NOT NULL REFERENCES devices(mac),
    zone text NOT NULL,
    address inet NOT NULL,
    source text NOT NULL,
    first_observed timestamptz NOT NULL,
    last_observed timestamptz NOT NULL,
    last_activity timestamptz,
    lease_expires timestamptz,
    PRIMARY KEY(mac, zone, address)
);
CREATE TABLE IF NOT EXISTS events (
    id bigserial PRIMARY KEY,
    observed_at timestamptz NOT NULL,
    kind text NOT NULL CHECK (kind IN ('new_identity','new_zone','new_address')),
    mac text NOT NULL REFERENCES devices(mac),
    zone text NOT NULL,
    address inet NOT NULL,
    source text NOT NULL,
    hostname text NOT NULL DEFAULT '',
    published boolean NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS events_observed_at ON events(observed_at DESC);
CREATE INDEX IF NOT EXISTS events_unpublished ON events(id) WHERE NOT published;
