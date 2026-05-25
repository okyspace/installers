#!/bin/bash
# ─── Test 03: Failover — Kill Primary ───
# Deletes the current primary pod and measures how long the operator
# takes to promote a new primary and restore the cluster to full health.
#
# Usage:
#   ./03-failover-kill-primary.sh <cluster-name> [namespace]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
parse_args "$0" "$@"

header "Failover Test — Kill Primary (${CLUSTER_NAME}, ns: ${NAMESPACE})"

# ──────────────────────────────────────────────
# 1. Pre-flight
# ──────────────────────────────────────────────
TARGET=$(get_target_instances)
if [ "$TARGET" -lt 2 ]; then
    fail "Cluster has only $TARGET instance(s) — need ≥ 2 for failover testing"
    exit 1
fi

wait_for_ready 60

OLD_PRIMARY=$(get_primary_pod)
ok "Current primary: $OLD_PRIMARY"
info "Replicas:"
get_replica_pods | while read -r r; do echo "  - $r"; done

# ──────────────────────────────────────────────
# 2. Kill the primary
# ──────────────────────────────────────────────
echo ""
warn "Deleting primary pod $OLD_PRIMARY..."
KILL_EPOCH=$(now_epoch)
kubectl delete pod "$OLD_PRIMARY" -n "$NAMESPACE" --grace-period=0 --force 2>/dev/null || \
kubectl delete pod "$OLD_PRIMARY" -n "$NAMESPACE"

info "Primary pod deleted at $(date -d @$KILL_EPOCH '+%H:%M:%S' 2>/dev/null || date -r $KILL_EPOCH '+%H:%M:%S' 2>/dev/null || echo $KILL_EPOCH)"

# ──────────────────────────────────────────────
# 3. Watch for new primary promotion
# ──────────────────────────────────────────────
info "Waiting for new primary to be elected..."
TIMEOUT=120
ELAPSED=0
NEW_PRIMARY=""

while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    CANDIDATE=$(get_primary_pod 2>/dev/null || echo "")
    if [ -n "$CANDIDATE" ] && [ "$CANDIDATE" != "$OLD_PRIMARY" ]; then
        NEW_PRIMARY=$CANDIDATE
        PROMOTE_EPOCH=$(now_epoch)
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done

if [ -z "$NEW_PRIMARY" ]; then
    fail "No new primary detected within ${TIMEOUT}s"
    exit 1
fi

PROMOTE_TIME=$((PROMOTE_EPOCH - KILL_EPOCH))
ok "New primary elected: $NEW_PRIMARY (took ${PROMOTE_TIME}s)"

# ──────────────────────────────────────────────
# 4. Wait for full cluster recovery
# ──────────────────────────────────────────────
info "Waiting for cluster to return to $TARGET ready instances..."
RECOVERY_START=$(now_epoch)

if wait_for_ready 180; then
    RECOVERY_TIME=$(( $(now_epoch) - KILL_EPOCH ))
    ok "Full recovery in ${RECOVERY_TIME}s"
else
    RECOVERY_TIME=$(( $(now_epoch) - KILL_EPOCH ))
    warn "Cluster not fully recovered after ${RECOVERY_TIME}s"
fi

# ──────────────────────────────────────────────
# 5. Verify old primary rejoined as replica
# ──────────────────────────────────────────────
info "Checking if $OLD_PRIMARY rejoined as replica..."
sleep 5  # give it a moment

OLD_ROLE=$(kubectl get pod "$OLD_PRIMARY" -n "$NAMESPACE" \
    -o jsonpath='{.metadata.labels.cnpg\.io/instanceRole}' 2>/dev/null || echo "not-found")

if [ "$OLD_ROLE" == "replica" ]; then
    ok "$OLD_PRIMARY rejoined as replica"
elif [ "$OLD_ROLE" == "not-found" ]; then
    info "$OLD_PRIMARY pod not yet recreated — may still be starting"
else
    warn "$OLD_PRIMARY has role '$OLD_ROLE' (expected 'replica')"
fi

# ──────────────────────────────────────────────
# 6. Summary
# ──────────────────────────────────────────────
header "Failover Summary"
echo "  Old primary        : $OLD_PRIMARY"
echo "  New primary        : $NEW_PRIMARY"
echo "  Promotion time     : ${PROMOTE_TIME}s"
echo "  Full recovery time : ${RECOVERY_TIME}s"
echo "  Old primary role   : $OLD_ROLE"

header "Failover Test Complete"
