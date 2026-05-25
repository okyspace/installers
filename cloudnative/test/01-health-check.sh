#!/bin/bash
# ─── Test 01: Cluster Health Check ───
# Verifies the cluster is running with the expected instance count,
# all replicas are streaming, and services are resolvable.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
parse_args "$0" "$@"

header "Cluster Health Check — ${CLUSTER_NAME} (ns: ${NAMESPACE})"

# ──────────────────────────────────────────────
# 1. Check cluster resource exists
# ──────────────────────────────────────────────
info "Checking cluster resource..."
if ! kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE" &>/dev/null; then
    fail "Cluster '$CLUSTER_NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi
ok "Cluster resource exists"

# ──────────────────────────────────────────────
# 2. Instance count
# ──────────────────────────────────────────────
TARGET=$(get_target_instances)
READY=$(get_ready_instances)
info "Target instances: $TARGET | Ready instances: $READY"

if [ "$READY" == "$TARGET" ]; then
    ok "All $TARGET instances are ready"
else
    fail "Expected $TARGET ready instances, got $READY"
    exit 1
fi

# ──────────────────────────────────────────────
# 3. Primary identification
# ──────────────────────────────────────────────
PRIMARY=$(get_primary_pod)
if [ -z "$PRIMARY" ]; then
    fail "No primary pod detected"
    exit 1
fi
ok "Primary pod: $PRIMARY"

# ──────────────────────────────────────────────
# 4. Replica streaming status
# ──────────────────────────────────────────────
info "Checking replication status..."
REPLICAS=$(get_replica_pods)
REPLICA_COUNT=0
ALL_STREAMING=true

for r in $REPLICAS; do
    REPLICA_COUNT=$((REPLICA_COUNT + 1))
    # Check if the replica is in streaming state via pod labels
    STATE=$(kubectl get pod "$r" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.cnpg\.io/instanceRole}' 2>/dev/null || echo "unknown")
    if [ "$STATE" == "replica" ]; then
        ok "  $r → role=replica (streaming)"
    else
        warn "  $r → role=$STATE (unexpected)"
        ALL_STREAMING=false
    fi
done

if [ "$REPLICA_COUNT" -eq 0 ]; then
    warn "No replicas found — cluster may be running in single-instance mode"
elif $ALL_STREAMING; then
    ok "All $REPLICA_COUNT replicas are streaming"
else
    warn "Some replicas are not in expected state"
fi

# ──────────────────────────────────────────────
# 5. Service endpoints
# ──────────────────────────────────────────────
info "Checking services..."
for SVC in $(get_rw_service) $(get_ro_service) $(get_r_service); do
    if kubectl get svc "$SVC" -n "$NAMESPACE" &>/dev/null; then
        ENDPOINTS=$(kubectl get endpoints "$SVC" -n "$NAMESPACE" -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)
        if [ -n "$ENDPOINTS" ]; then
            ok "  $SVC → endpoints: $ENDPOINTS"
        else
            warn "  $SVC → exists but no endpoints"
        fi
    else
        warn "  $SVC → not found"
    fi
done

# ──────────────────────────────────────────────
# 6. cnpg plugin status (if available)
# ──────────────────────────────────────────────
if command -v kubectl-cnpg &>/dev/null || kubectl cnpg version &>/dev/null 2>&1; then
    info "Running 'kubectl cnpg status'..."
    echo ""
    kubectl cnpg status "$CLUSTER_NAME" -n "$NAMESPACE" || true
    echo ""
else
    info "kubectl cnpg plugin not installed — skipping detailed status"
fi

header "Health Check Complete"
