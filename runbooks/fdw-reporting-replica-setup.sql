-- postgres_fdw: read reporting data from a remote PostgreSQL instance
-- Replace hosts, database names, and credentials for your environment.

-- ON REPORTING SERVER
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

CREATE SERVER reporting_source
  FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (host 'CHANGE_ME_SOURCE_HOST', port '5432', dbname 'CHANGE_ME_DB');

CREATE USER MAPPING FOR CURRENT_USER
  SERVER reporting_source
  OPTIONS (user 'fdw_readonly', password 'CHANGE_ME');

-- Import foreign schema (example)
CREATE SCHEMA IF NOT EXISTS reporting_remote;
IMPORT FOREIGN SCHEMA reporting_schema
  FROM SERVER reporting_source
  INTO reporting_remote;

-- Verify
SELECT foreign_table_schema, foreign_table_name
FROM information_schema.foreign_tables
WHERE foreign_table_schema = 'reporting_remote';
