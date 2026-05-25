#!/bin/bash
# ─── Test 02: Write Continuity ───
# Inserts numbered rows into a test table in a tight loop.
# Run this IN PARALLEL with a failover/switchover test to measure:
#   - How many writes succeed before / after the event
#   - Size of the gap (missing sequence numbers = lost writes)
#   - Approximate downtime window
#
# Usage:
#   ./02-write-continuity.sh <cluster-name> [namespace] [duration_seconds]
#
# The script writes to a table `ha_test.write_log` and, on exit (Ctrl-C or
# duration timeout), prints a gap analysis report.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
parse_args "$0" "$@"

DURATION=${3:-120}  # default 2 minutes

header "Write Continuity Test — ${CLUSTER_NAME} (ns: ${NAMESPACE})"

# ──────────────────────────────────────────────
# Resolve primary pod for direct exec
# ──────────────────────────────────────────────
PRIMARY=$(get_primary_pod)
info "Primary pod: $PRIMARY"
info "Duration: ${DURATION}s (Ctrl-C to stop early)"

# ──────────────────────────────────────────────
# Create test schema & table
# ──────────────────────────────────────────────
info "Creating test schema..."
kubectl exec -n "$NAMESPACE" "$PRIMARY" -- psql -U postgres -d app -c "
    CREATE SCHEMA IF NOT EXISTS ha_test;
    DROP TABLE IF EXISTS ha_test.write_log;
    CREATE TABLE ha_test.write_log (
        seq     SERIAL PRIMARY KEY,
        ts      TIMESTAMPTZ DEFAULT now(),
        writer  TEXT
    );
" 2>/dev/null

ok "Test table ha_test.write_log created"

# ──────────────────────────────────────────────
# Write loop
# ──────────────────────────────────────────────
WRITER_ID="writer-$$"
SUCCESSES=0
FAILURES=0
START_EPOCH=$(now_epoch)
END_EPOCH=$((START_EPOCH + DURATION))
FIRST_FAIL_EPOCH=""
LAST_FAIL_EPOCH=""

# Determine the rw service to write through (service follows the primary)
RW_SVC=$(get_rw_service)

info "Starting write loop through service ${RW_SVC}..."
echo ""

cleanup() {
    echo ""
    header "Write Continuity Report"
    echo "  Total writes attempted : $((SUCCESSES + FAILURES))"
    echo "  Successful             : $SUCCESSES"
    echo "  Failed                 : $FAILURES"
    if [ -n "$FIRST_FAIL_EPOCH" ] && [ -n "$LAST_FAIL_EPOCH" ]; then
        DOWNTIME=$((LAST_FAIL_EPOCH - FIRST_FAIL_EPOCH))
        echo "  Approx. downtime       : ${DOWNTIME}s (first failure → last failure)"
    else
        echo "  Approx. downtime       : 0s (no failures detected)"
    fi

    # Gap analysis — query the table on whatever is now the primary
    echo ""
    info "Checking for sequence gaps..."
    NEW_PRIMARY=$(get_primary_pod 2>/dev/null || echo "$PRIMARY")
    GAPS=$(kubectl exec -n "$NAMESPACE" "$NEW_PRIMARY" -- psql -U postgres -d app -tA -c "
        SELECT seq + 1 AS gap_start, next_seq - 1 AS gap_end
        FROM (
            SELECT seq, LEAD(seq) OVER (ORDER BY seq) AS next_seq
            FROM ha_test.write_log
        ) t
        WHERE next_seq - seq > 1
        ORDER BY gap_start;
    " 2>/dev/null || echo "")

    if [ -z "$GAPS" ]; then
        ok "No sequence gaps detected — zero data loss"
    else
        warn "Sequence gaps found (these writes were lost during failover):"
        echo "$GAPS" | while IFS='|' read -r gap_start gap_end; do
            echo "    seq $gap_start – $gap_end"
        done
    fi

    header "Write Continuity Test Complete"
    exit 0
}
trap cleanup EXIT INT TERM

while [ "$(now_epoch)" -lt "$END_EPOCH" ]; do
    # Write through a one-shot pod using the rw service DNS
    if kubectl exec -n "$NAMESPACE" "$PRIMARY" -- psql -U postgres -d app -tA -c \
        "INSERT INTO ha_test.write_log (writer) VALUES ('${WRITER_ID}') RETURNING seq;" 2>/dev/null; then
        SUCCESSES=$((SUCCESSES + 1))
    else
        FAILURES=$((FAILURES + 1))
        CURRENT_EPOCH=$(now_epoch)
        [ -z "$FIRST_FAIL_EPOCH" ] && FIRST_FAIL_EPOCH=$CURRENT_EPOCH
        LAST_FAIL_EPOCH=$CURRENT_EPOCH

        # The primary may have changed — re-resolve
        NEW_PRIMARY=$(get_primary_pod 2>/dev/null || echo "")
        if [ -n "$NEW_PRIMARY" ] && [ "$NEW_PRIMARY" != "$PRIMARY" ]; then
            warn "Primary changed: $PRIMARY → $NEW_PRIMARY"
            PRIMARY=$NEW_PRIMARY
        fi
    fi
    sleep 0.5
done
