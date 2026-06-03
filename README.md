# PostgreSQL HA & Replication

Streaming replication, planned failover/failback, **Pgpool-II** automation, logical replication, **postgres_fdw** reporting setup, and WAL/backup maintenance scripts for enterprise PostgreSQL (14–17).

**Author:** [Achille Cesar Ntwali](https://github.com/achille250) · Kigali, Rwanda

---

## Overview

This repository contains production-oriented automation and runbooks used on large transactional PostgreSQL platforms (public financial / banking workloads). All hostnames and credentials use placeholders—configure for your environment before use.

---

## Repository structure

```
postgresql-ha-replication/
├── scripts/
│   ├── add_replica_v1.sh              # Standby setup (dry-run / auto modes, SCRAM, slots)
│   ├── add_replica(withnoupgrade).sh  # Replica without version upgrade
│   ├── pgpool_auto_attach.sh          # Pgpool node attach automation
│   ├── pgpool_log_sanitize.sh         # Pgpool log hygiene
│   ├── pglogical.sql                  # Logical replication helpers
│   ├── cleanbackup.sh                 # Backup directory rotation by disk threshold
│   ├── cleanwals.sh / cleanwalarchive.sh / copybackup.sh
│   └── upgrade_pg15_to_pg17_simple.sh # Simplified major upgrade helper
├── runbooks/
│   ├── planned-failover-failback.txt
│   ├── promote-replica-to-primary.txt
│   ├── logical-replication-notes.txt
│   ├── logical-replication-with-physical-slot.txt
│   ├── fdw-reporting-replica-setup.sql
│   ├── taking a basebakup on postgres.txt
│   └── basebackup replica.txt
└── sql/
    └── replication_monitoring.sql     # Lag, slots, recovery status
```

---

## Quick start

### Add a streaming replica (Ubuntu, PG 14–17)

```bash
# On replica: store replication password securely, then:
sudo ./scripts/add_replica_v1.sh --dry-run   # validate
sudo ./scripts/add_replica_v1.sh --auto      # validate + run
```

Prerequisites: replication role on primary, `pg_hba.conf` entry for replica IP, SCRAM authentication.

### Monitor replication

```sql
\i sql/replication_monitoring.sql
```

---

## Related repositories

| Repo | Focus |
|------|--------|
| [postgresql-upgrade-toolkit](https://github.com/achille250/postgresql-upgrade-toolkit) | PG 15→17 upgrade |
| [postgresql-monitoring-stack](https://github.com/achille250/postgresql-monitoring-stack) | Prometheus, Grafana, pgBadger |
| [postgresql-security-rbac](https://github.com/achille250/postgresql-security-rbac) | RBAC, RLS, audit |
| [postgresql-performance-tuning](https://github.com/achille250/postgresql-performance-tuning) | Indexes, EXPLAIN |
| [postgresql-data-migration](https://github.com/achille250/postgresql-data-migration) | dblink migration |

---

## License

MIT — see [LICENSE](LICENSE).
