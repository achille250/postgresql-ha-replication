#!/usr/bin/env bash
# Version: v1.4 (U24) – 2025-11-10
#
# add_replica.sh — PostgreSQL Standby (Replica) Setup for Ubuntu (24.04 tested; works for PG 14–17)
#
# PURPOSE (What this script does)
#   • Creates a secure, no-prompt replication setup from a PRIMARY to this REPLICA.
#   • Uses one authoritative secret file for the password, and derives a .pgpass from it.
#   • Supports three modes: --dry-run (validate), --auto (validate then run), default (real run).
#
# WHY `#!/usr/bin/env bash`?
#   • Portability: bash path may differ across systems. Using /usr/bin/env finds the correct bash.
#
# TOPOLOGY (Quick diagram)
#   PRIMARY (${PRIMARY_HOST}:5433)
#           │  streaming WAL
#           └──────────────►  REPLICA (this server)
#
# --- PREREQUISITES (COMPACT + EXPLAINED) ---------------------------------------
# 1) On PRIMARY (example host/port shown; adjust to your environment)
#      • Ensure password_encryption = 'scram-sha-256' (recommended for 14–17)
#          ALTER SYSTEM SET password_encryption='scram-sha-256';
#          SELECT pg_reload_conf();
#      • Create a replication role with LOGIN + REPLICATION:
#          CREATE ROLE replica WITH REPLICATION LOGIN ENCRYPTED PASSWORD '<<secret>>';
#      • Add pg_hba.conf entry for this replica's IP (example <REPLICA_IP>/32):
#          host  replication  replica  <REPLICA_IP>/32  scram-sha-256
#      • Reload config after editing pg_hba.conf.
#
# 2) On REPLICA (this server) — store password securely for the postgres user
#      sudo install -d -o postgres -g postgres /var/lib/postgresql/.secrets
#      sudo install -m 600 -o postgres -g postgres /dev/stdin \
#           /var/lib/postgresql/.secrets/pg_repl.pw <<'PW'
#      <<secret>>
#      PW
#    EXPLANATION:
#      • Keep the single source of truth in pg_repl.pw (owner=postgres or root; mode=600).
#      • The script will build .pgpass from this secret (ephemeral for dry-run, persistent for real run).
#
# 3) Run modes ON THE REPLICA (recommended workflow)
#      a) Validate first (no changes):
#           sudo ./add_replica.sh --dry-run
#      b) Or one-shot validate+run:
#           sudo ./add_replica.sh --auto
#      c) Or run immediately (no validation step):
#           sudo ./add_replica.sh
#
# 4) About `set -Eeuo pipefail`
#      • -e: exit on any error; -u: treat unset variables as errors; -o pipefail: catch failures in pipelines.
#      • -E: make traps on ERR propagate into functions/subshells. Together: fail-fast + safer scripts.
#
# DO (Best Practices)
#   ✓ Run as root (the script runs psql/pg_basebackup as postgres internally).
#   ✓ Use SCRAM-SHA-256 on the PRIMARY for secure passwords.
#   ✓ Keep DATA_DIR empty before basebackup to avoid accidental overwrite.
#
# DO NOT
#   ✗ Do not reuse old replication slots unless you are absolutely sure it's safe.
#   ✗ Do not relax file permissions on secrets (.pgpass must be 600 for the user that reads it).
#
# 30-SECOND ROLLBACK (If something goes wrong after real run)
#   • systemctl stop postgresql@17-main
#   • rm -rf /opt/postgresql17              # remove the partial data directory (adjust path if changed)
#   • (Optional) drop slot on PRIMARY if created: SELECT pg_drop_replication_slot('standbyX');
#   • Fix the cause (pg_hba, network, password), then rerun --dry-run or --auto.
#
# ------------------------------------------------------------------------------
# INTERNAL NOTES (for maintainers/instructors)
#   • This script ALWAYS runs libpq clients as the postgres user with a .pgpass file (no prompts).
#   • In --dry-run, .pgpass is ephemeral under /var/lib/postgresql and auto-deleted.
#   • In real run, a persistent .pgpass is created atomically from the secret file.
#   • Slots are auto-numbered: standby1, standby2, ... (never reuses by default for safety).
#!!!big note make sure all extensions on primary are installed on replica also
# ------------------------------------------------------------------------------
#
set -Eeuo pipefail
IFS=$'\n\t'
 
# =========================
# CONFIGURATION (edit here)
# =========================
PRIMARY_HOST="${PRIMARY_HOST:-CHANGE_ME_PRIMARY_HOST}"  # Primary host/IP (or export PRIMARY_HOST)
PRIMARY_PORT="5433"              # Primary port
REPL_USER="replica"              # Replication user (must exist on Primary)
 
REPLICA_PORT="5433"              # Port for the local replica cluster
SLOT_PREFIX="standby"            # New replicas get standby1, standby2, ...
DATA_DIR="/opt/postgresql17"     # Data directory for this replica
LOG_DIR="/BKP/postgres17_log"    # Log directory for this replica
SERVICE_NAME="postgresql@17-main" # Systemd service name for the PG cluster
 
PW_FILE="/var/lib/postgresql/.secrets/pg_repl.pw"   # Single source of secret
PGPASS_PERSIST="/var/lib/postgresql/.pgpass"        # Persistent .pgpass path
PGPASS_RUNTIME=""                                    # Ephemeral path (dry-run) or same as persistent (real run)
 
# =====================
# MODE & FLAG HANDLING
# =====================
DRY_RUN="false"
AUTO="false"
case "${1:-}" in
  --dry-run) DRY_RUN="true" ;;
  --auto)    DRY_RUN="true"; AUTO="true" ;;
  ""|*)      : ;;  # default: real run
esac
 
# ================
# LOGGING HELPERS
# ================
info()  { printf "\e[34m[INFO]\e[0m  %s\n" "$*"; }
ok()    { printf "\e[32m[OK]\e[0m    %s\n" "$*"; }
warn()  { printf "\e[33m[WARN]\e[0m  %s\n" "$*"; }
err()   { printf "\e[31m[ERROR]\e[0m %s\n" "$*" 1>&2; }
 
# ==================
# RUNTIME UTILITIES
# ==================
must_root() {
  # Teach: We need root because we create directories, manage service, and sudo to postgres.
  if [[ "${EUID}" -ne 0 ]]; then
    err "Please run as root: sudo ./add_replica.sh [--dry-run|--auto]"
    exit 1
  fi
}
 
ensure_tools() {
  # Teach: Validate and install minimal dependencies on Ubuntu.
  command -v ip   >/dev/null 2>&1 || { apt-get update -y; apt-get install -y iproute2 >/dev/null; }
  command -v nc   >/dev/null 2>&1 || apt-get install -y netcat-openbsd >/dev/null
  command -v psql >/dev/null 2>&1 || true
  command -v mktemp >/dev/null 2>&1 || true
}
 
replica_ip_guess() {
  # Teach: First try the interface that reaches the PRIMARY, else take the first 10.x address.
  local ip_guess=""
  ip_guess="$(ip -4 route get "${PRIMARY_HOST}" 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++){if($i=="src"){print $(i+1);exit}}}')"
  if [[ -z "${ip_guess}" ]]; then
    ip_guess="$(ip -4 addr show | awk '/inet 10\\./{gsub(/\/.*/,"",$2); print $2; exit}')"
  fi
  printf "%s" "${ip_guess}"
}
 
# Build an ephemeral (dry-run) or persistent (real run) .pgpass from PW_FILE, owned by postgres.
prepare_pgpass_from_secret() {
  local host="${PRIMARY_HOST}" port="${PRIMARY_PORT}" user="${REPL_USER}"
  local pw_file="${PW_FILE}" out=""
  local pw line
  pw="$(< "${pw_file}")"
  line="${host}:${port}:*:${user}:${pw}"
 
  if [[ "${DRY_RUN}" == "true" ]]; then
    # DRY-RUN: ephemeral file created safely with umask 077 (mode 600)
    out="$(sudo -u postgres mktemp -p /var/lib/postgresql .pgpass.XXXXXX)"
    sudo -u postgres bash -c "umask 077 && printf '%s\n' '${line}' > '${out}'"
    sudo chown postgres:postgres "${out}"
    sudo chmod 600 "${out}"
    PGPASS_RUNTIME="${out}"
    info "Created ephemeral .pgpass for dry-run at ${PGPASS_RUNTIME}"
  else
    # REAL RUN: persistent file created atomically
    install -d -m 700 -o postgres -g postgres /var/lib/postgresql
    local tmp="/var/lib/postgresql/.pgpass.tmp"
    sudo -u postgres bash -c "umask 077 && printf '%s\n' '${line}' > '${tmp}'"
    sudo chown postgres:postgres "${tmp}"
    sudo chmod 600 "${tmp}"
    mv "${tmp}" "${PGPASS_PERSIST}"
    PGPASS_RUNTIME="${PGPASS_PERSIST}"
    ok "Persistent .pgpass prepared at ${PGPASS_PERSIST}"
  fi
}
 
# Run a SQL statement on the PRIMARY via psql with .pgpass, as postgres.
psql_pgpass() {
  local sql="$1"
  sudo -u postgres PGPASSFILE="${PGPASS_RUNTIME}" psql -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" -U "${REPL_USER}" -d postgres -At -c "${sql}"
}
 
# Run a SQL statement locally (replica) via psql, as postgres.
psql_local() {
  sudo -u postgres PGPASSFILE="${PGPASS_RUNTIME}" psql -p "${REPLICA_PORT}" -d postgres -At -c "$1"
}
 
# Clean up ephemeral .pgpass after dry-run.
cleanup_ephemeral_pgpass() {
  if [[ "${DRY_RUN}" == "true" && -n "${PGPASS_RUNTIME}" && -f "${PGPASS_RUNTIME}" ]]; then
    sudo -u postgres rm -f "${PGPASS_RUNTIME}" || true
    info "Removed ephemeral .pgpass (${PGPASS_RUNTIME})."
    PGPASS_RUNTIME=""
  fi
}
 
# =============
# MAIN ROUTINE
# =============
must_root
ensure_tools
 
REPLICA_IP="$(replica_ip_guess)"
REPLICA_IP="${REPLICA_IP:-$(hostname -I | awk '{print $1}')}"
info "Replica local IP detected: ${REPLICA_IP}"
 
# Validate the secret file (single source of truth)
if [[ ! -f "${PW_FILE}" ]]; then
  err "Password file '${PW_FILE}' does not exist. See prerequisites."
  exit 1
fi
if [[ ! -s "${PW_FILE}" ]]; then
  err "Password file '${PW_FILE}' is empty."
  exit 1
fi
OWNER="$(stat -c '%U' "${PW_FILE}")"
PERM="$(stat -c '%a' "${PW_FILE}")"
if [[ "${OWNER}" != "postgres" && "${OWNER}" != "root" ]]; then
  err "Password file must be owned by 'postgres' or 'root' (current: ${OWNER})."
  exit 1
fi
if [[ "${PERM}" != "600" ]]; then
  err "Password file must have permissions 600 (current: ${PERM})."
  exit 1
fi
ok "Password file validated (owner=${OWNER}, mode=${PERM})."
 
# Prepare .pgpass (ephemeral for dry-run; persistent for real run)
prepare_pgpass_from_secret
 
# ---------- DRY-RUN VALIDATIONS (non-destructive) ------------------------------
info "Checking TCP reachability to primary ${PRIMARY_HOST}:${PRIMARY_PORT} ..."
if ! nc -z -w 3 "${PRIMARY_HOST}" "${PRIMARY_PORT}"; then
  cleanup_ephemeral_pgpass
  err "Primary ${PRIMARY_HOST}:${PRIMARY_PORT} is not reachable."
  exit 1
fi
ok "TCP connectivity OK."
 
info "Checking authentication to primary using replication credentials (.pgpass) ..."
if ! psql_pgpass "SELECT 1;" >/dev/null 2>&1; then
  cleanup_ephemeral_pgpass
  err "Authentication failed for user '${REPL_USER}' using .pgpass."
  exit 1
fi
ok "Authentication OK."
 
info "Verifying replication role exists and has REPLICATION attribute ..."
ROLE_OK="$(psql_pgpass "SELECT 1 FROM pg_roles WHERE rolname='${REPL_USER}' AND rolreplication;")" || true
if [[ "${ROLE_OK}" != "1" ]]; then
  cleanup_ephemeral_pgpass
  err "Role '${REPL_USER}' does not exist or lacks REPLICATION privilege on primary."
  exit 1
fi
ok "Replication role is valid."
 
info "Checking pg_hba has replication entries for '${REPL_USER}' ..."
set +e
HBA_COUNT="$(psql_pgpass "SELECT count(*) FROM pg_hba_file_rules WHERE database='replication' AND (user_name='${REPL_USER}' OR user_name='all');" 2>/dev/null)"
PG_HBA_QUERY_RC=$?
set -e
if [[ ${PG_HBA_QUERY_RC} -ne 0 ]]; then
  warn "Could not read pg_hba_file_rules (likely superuser-only). Will rely on connection tests."
else
  if [[ -z "${HBA_COUNT}" || "${HBA_COUNT}" == "0" ]]; then
    cleanup_ephemeral_pgpass
    err "No pg_hba.conf entry for database='replication' (user '${REPL_USER}'). Add: host replication ${REPL_USER} ${REPLICA_IP}/32 scram-sha-256"
    exit 1
  fi
  ok "pg_hba has replication entries (verify IP/subnet correctness)."
fi
 
info "Auto-detecting next available slot/application_name with prefix '${SLOT_PREFIX}' ..."
EXISTING="$(psql_pgpass "SELECT slot_name FROM pg_replication_slots WHERE slot_name ~ '^${SLOT_PREFIX}[0-9]+$' ORDER BY slot_name;")" || true
NEXT_NUM=1
if [[ -n "${EXISTING}" ]]; then
  MAX_N=0
  while IFS= read -r s; do
    n="${s#${SLOT_PREFIX}}"
    n="${n//[^0-9]/}"
    if [[ -n "${n}" && "${n}" -gt "${MAX_N}" ]]; then MAX_N="${n}"; fi
  done <<< "${EXISTING}"
  NEXT_NUM=$((MAX_N + 1))
fi
SLOT_NAME="${SLOT_PREFIX}${NEXT_NUM}"
APP_NAME="${SLOT_NAME}"
ok "Selected slot/application_name: ${SLOT_NAME}"
 
SLOT_EXISTS="$(psql_pgpass "SELECT 1 FROM pg_replication_slots WHERE slot_name='${SLOT_NAME}';")" || true
if [[ "${SLOT_EXISTS}" == "1" ]]; then
  CREATE_SLOT_FLAG="no"
  info "Slot '${SLOT_NAME}' already exists; pg_basebackup will run without -C."
else
  CREATE_SLOT_FLAG="yes"
  info "Slot '${SLOT_NAME}' does not exist; pg_basebackup will create it with -C."
fi
 
# End of dry-run checks
if [[ "${DRY_RUN}" == "true" ]]; then
  info "[DRY RUN COMPLETE] No blocking errors detected."
  cleanup_ephemeral_pgpass
  if [[ "${AUTO}" == "true" && -z "${ALREADY_AUTO_RERUN:-}" ]]; then
    info "[AUTO] Proceeding to real run now..."
    # Restart script in real-run mode (fresh process); prevent infinite loop with guard.
    exec env ALREADY_AUTO_RERUN=1 "$0"
  fi
  exit 0
fi
 
# -----------------
# REAL RUN (action)
# -----------------
info "Stopping & disabling ${SERVICE_NAME} if running ..."
systemctl stop "${SERVICE_NAME}" || true
systemctl disable "${SERVICE_NAME}" || true
 
info "Creating data and log directories ..."
install -d -m 700 -o postgres -g postgres "${DATA_DIR}"
install -d -m 750 -o postgres -g postgres "${LOG_DIR}"
 
info "Running pg_basebackup to '${DATA_DIR}' ..."
if [[ -n "$(ls -A "${DATA_DIR}" 2>/dev/null || true)" ]]; then
  err "DATA_DIR '${DATA_DIR}' is not empty. Aborting to avoid overwriting."
  exit 1
fi
# Ensure persistent .pgpass exists for the real run
if [[ ! -f "${PGPASS_PERSIST}" ]]; then
  prepare_pgpass_from_secret
fi
if [[ "${CREATE_SLOT_FLAG}" == "yes" ]]; then
  sudo -u postgres PGPASSFILE="${PGPASS_PERSIST}" pg_basebackup \
    -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" \
    -D "${DATA_DIR}" -U "${REPL_USER}" \
    -Fp -v -R -X stream -C -S "${SLOT_NAME}"
else
  sudo -u postgres PGPASSFILE="${PGPASS_PERSIST}" pg_basebackup \
    -h "${PRIMARY_HOST}" -p "${PRIMARY_PORT}" \
    -D "${DATA_DIR}" -U "${REPL_USER}" \
    -Fp -v -R -X stream -S "${SLOT_NAME}"
fi
ok "Base backup completed."
 
# Ensure application_name is present for visibility on PRIMARY
AUTO_CONF="${DATA_DIR}/postgresql.auto.conf"
if [[ -f "${AUTO_CONF}" && -w "${AUTO_CONF}" ]]; then
  if grep -q "^primary_conninfo" "${AUTO_CONF}"; then
    if ! grep -q "application_name=" "${AUTO_CONF}"; then
      current="$(grep -oP "(?<=primary_conninfo = ').*(?=')" "${AUTO_CONF}" || true)"
      if [[ -n "${current}" ]]; then
        sed -i "s#^primary_conninfo = '.*'#primary_conninfo = '${current} application_name=${APP_NAME}'#g" "${AUTO_CONF}" || true
      else
        echo "primary_conninfo = 'application_name=${APP_NAME}'" >> "${AUTO_CONF}"
      fi
    fi
  fi
fi
 
# Configure cluster files
CONF_DIR="/etc/postgresql/17/main"
CONF_FILE="${CONF_DIR}/postgresql.conf"
HBA_FILE="${CONF_DIR}/pg_hba.conf"
info "Configuring cluster files in ${CONF_DIR} ..."
install -d -o postgres -g postgres "${CONF_DIR}"
touch "${CONF_FILE}" "${HBA_FILE}"
chown postgres:postgres "${CONF_FILE}" "${HBA_FILE}"
 
# data_directory
if grep -q "^data_directory" "${CONF_FILE}" 2>/dev/null; then
  sed -i -E "s|^data_directory *=.*|data_directory = '${DATA_DIR}'|g" "${CONF_FILE}" || true
else
  echo "data_directory = '${DATA_DIR}'" >> "${CONF_FILE}"
fi
# port
if grep -q "^port" "${CONF_FILE}" 2>/dev/null; then
  sed -i -E "s|^port *=.*|port = ${REPLICA_PORT}|g" "${CONF_FILE}" || true
else
  echo "port = ${REPLICA_PORT}" >> "${CONF_FILE}"
fi
# listen_addresses
if grep -q "^listen_addresses" "${CONF_FILE}" 2>/dev/null; then
  sed -i -E "s|^listen_addresses *=.*|listen_addresses = '*'|g" "${CONF_FILE}" || true
else
  echo "listen_addresses = '*'" >> "${CONF_FILE}"
fi
# logging
grep -q "^logging_collector" "${CONF_FILE}" || echo "logging_collector = on" >> "${CONF_FILE}"
if grep -q "^log_directory" "${CONF_FILE}" 2>/dev/null; then
  sed -i -E "s|^log_directory *=.*|log_directory = '${LOG_DIR}'|g" "${CONF_FILE}" || true
else
  echo "log_directory = '${LOG_DIR}'" >> "${CONF_FILE}"
fi
# Local monitoring convenience over TCP (scram)
grep -q "127.0.0.1/32" "${HBA_FILE}" || echo "host all all 127.0.0.1/32 scram-sha-256" >> "${HBA_FILE}"
grep -q "::1/128" "${HBA_FILE}" || echo "host all all ::1/128 scram-sha-256" >> "${HBA_FILE}"
 
# Start & verify
info "Enabling and starting ${SERVICE_NAME} ..."
systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl start "${SERVICE_NAME}"
sleep 3
systemctl --no-pager --full status "${SERVICE_NAME}" || true
 
# Post-start checks
if [[ "$(psql_local "SELECT pg_is_in_recovery();")" != "t" ]]; then
  err "Replica is not in recovery mode. Check logs in ${LOG_DIR} and configs."
  exit 1
fi
WAL_STATUS="$(psql_local 'SELECT COALESCE(status,'''') FROM pg_stat_wal_receiver;')" || true
 
# -----------
# SHORT SUMMARY
# -----------
echo
ok "Replica configured."
echo "Primary : ${PRIMARY_HOST}:${PRIMARY_PORT}"
echo "Slot    : ${SLOT_NAME} (created=${CREATE_SLOT_FLAG})"
echo "DataDir : ${DATA_DIR}"
echo "Service : ${SERVICE_NAME}"
echo "WAL RX  : ${WAL_STATUS}"
