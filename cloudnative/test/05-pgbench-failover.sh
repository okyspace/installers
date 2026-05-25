#!/bin/bash
# ─── Test 05: pgbench Stress Under Failover ───
# Runs pgbench, kills the primary mid-run, and reports TPS impact.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
parse_args "$0" "$@"

BENCH_DURATION=${3:-60}

header "pgbench Failover Stress (${CLUSTER_NAME}, ns: ${NAMESPACE})"

wait_for_ready 60
PRIMARY=$(get_primary_pod)
ok "Primary: $PRIMARY"

# Initialize pgbench tables
info "Initializing pgbench tables..."
kubectl exec -n "$NAMESPACE" "$PRIMARY" -- pgbench -U postgres -i app 2>/dev/null
ok "pgbench initialized"

# Start pgbench in background (via the primary pod)
info "Starting pgbench for ${BENCH_DURATION}s..."
kubectl exec -n "$NAMESPACE" "$PRIMARY" -- \
    pgbench -U postgres -T "$BENCH_DURATION" -c 2 -j 2 --progress=5 app &
BENCH_PID=$!

# Wait a bit for pgbench to ramp up, then kill the primary
KILL_DELAY=$((BENCH_DURATION / 3))
info "Will kill primary in ${KILL_DELAY}s..."
sleep "$KILL_DELAY"

OLD_PRIMARY=$PRIMARY
warn "Killing primary pod $OLD_PRIMARY..."
KILL_EPOCH=$(now_epoch)
kubectl delete pod "$OLD_PRIMARY" -n "$NAMESPACE" --grace-period=0 --force 2>/dev/null || true

# Wait for pgbench to finish (it will likely error out)
wait $BENCH_PID 2>/dev/null || true
PGBENCH_EXIT=$?

# Check new primary
sleep 5
NEW_PRIMARY=$(get_primary_pod 2>/dev/null || echo "unknown")
PROMOTE_TIME=$(( $(now_epoch) - KILL_EPOCH ))

header "pgbench Failover Results"
echo "  Old primary        : $OLD_PRIMARY"
echo "  New primary        : $NEW_PRIMARY"
echo "  Kill → promotion   : ~${PROMOTE_TIME}s"
echo "  pgbench exit code  : $PGBENCH_EXIT"

wait_for_ready 120
header "pgbench Failover Test Complete"
