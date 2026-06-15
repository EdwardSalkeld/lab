CREATE TABLE IF NOT EXISTS usages (
  consumption double precision NOT NULL,
  interval_start timestamptz NOT NULL,
  interval_end timestamptz NOT NULL,
  usage_type text NOT NULL,
  PRIMARY KEY (interval_start, usage_type)
);

GRANT USAGE ON SCHEMA public TO scheduler_writer;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE usages TO scheduler_writer;

GRANT USAGE ON SCHEMA public TO grafana;
GRANT SELECT ON TABLE usages TO grafana;
