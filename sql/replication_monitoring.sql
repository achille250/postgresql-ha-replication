-- Replication health monitoring queries

-- 1. Replication lag (on primary)
SELECT application_name, client_addr, state, sync_state,
       pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) AS sent_lag_bytes,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes
FROM pg_stat_replication;

-- 2. Replication slots
SELECT slot_name, slot_type, active, restart_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;

-- 3. On standby: am I in recovery?
SELECT pg_is_in_recovery();

-- 4. Last replay timestamp (standby)
SELECT pg_last_xact_replay_timestamp();
