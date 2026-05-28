#!/usr/bin/env bash
# dev-test-db-vacuum.sh — nightly VACUUM ANALYZE on all per-dev test DBs.
# Iterates pg_database WHERE datname LIKE 'vdole_%_test', runs VACUUM (ANALYZE) on each.
# Stable: skips non-existent / inaccessible DBs without failing the timer.
#
# Triggered by: /etc/systemd/system/dev-test-db-vacuum.timer (04:00 daily)

set -uo pipefail

LOG="/var/log/dev-test-db-vacuum.log"

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" | tee -a "$LOG"; }

log "=== nightly test-DB VACUUM start ==="

if ! command -v psql >/dev/null 2>&1; then
    log "ERROR: psql not found — exiting"
    exit 1
fi

# List all matching DBs (vdole_<alias>_test)
DBS=$(sudo -u postgres psql -tAc "SELECT datname FROM pg_database WHERE datname LIKE 'vdole_%_test' ORDER BY datname;" 2>>"$LOG")

if [ -z "$DBS" ]; then
    log "no test DBs found (pattern: vdole_%_test) — nothing to do"
    exit 0
fi

COUNT_OK=0
COUNT_FAIL=0

for db in $DBS; do
    [ -n "$db" ] || continue
    log "  VACUUM (ANALYZE) $db ..."
    # ANALYZE-only, not FULL — FULL takes exclusive lock & rewrites tables.
    # Per-dev test DBs are small + autovacuum already handles routine bloat;
    # this just refreshes statistics and reclaims dead tuples from last day's tests.
    if sudo -u postgres psql -d "$db" -c "VACUUM (VERBOSE, ANALYZE);" >>"$LOG" 2>&1; then
        COUNT_OK=$((COUNT_OK + 1))
    else
        log "    FAILED — $db (continuing with next)"
        COUNT_FAIL=$((COUNT_FAIL + 1))
    fi
done

log "=== done: $COUNT_OK ok, $COUNT_FAIL failed ==="

# Rotate log if larger than 5 MB
if [ -f "$LOG" ] && [ "$(stat -c%s "$LOG" 2>/dev/null || echo 0)" -gt 5242880 ]; then
    mv "$LOG" "${LOG}.1"
    : > "$LOG"
fi
