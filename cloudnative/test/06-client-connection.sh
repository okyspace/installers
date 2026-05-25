#!/bin/bash
# ─── Test 06: Client Connection Test ───
# Deploys a psql client pod and verifies connectivity through
# the -rw, -ro, and -r services.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
parse_args "$0" "$@"

header "Client Connection Test (${CLUSTER_NAME}, ns: ${NAMESPACE})"

wait_for_ready 60

# Get superuser password
PASSWORD=$(get_superuser_password 2>/dev/null || echo "")
if [ -z "$PASSWORD" ]; then
    warn "Could not retrieve superuser password — trying app user secret"
    PASSWORD=$(kubectl get secret "${CLUSTER_NAME}-app" -n "$NAMESPACE" \
        -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "")
fi

DB_USER="postgres"
DB_NAME="app"
CLIENT_POD="cnpg-test-client-$$"

# Cleanup on exit
cleanup() {
    kubectl delete pod "$CLIENT_POD" -n "$NAMESPACE" --ignore-not-found &>/dev/null || true
}
trap cleanup EXIT INT TERM

# Deploy a lightweight psql client pod
info "Creating test client pod..."
kubectl run "$CLIENT_POD" -n "$NAMESPACE" \
    --image=postgres:17 \
    --restart=Never \
    --env="PGPASSWORD=$PASSWORD" \
    --command -- sleep 300 &>/dev/null

wait_for_pod "$CLIENT_POD" 60

# Test each service
for SVC_SUFFIX in rw ro r; do
    SVC_HOST="${CLUSTER_NAME}-${SVC_SUFFIX}.${NAMESPACE}.svc"
    info "Testing service: $SVC_HOST"

    RESULT=$(kubectl exec -n "$NAMESPACE" "$CLIENT_POD" -- \
        psql -h "$SVC_HOST" -U "$DB_USER" -d "$DB_NAME" -tA -c \
        "SELECT inet_server_addr() || ' (' || CASE WHEN pg_is_in_recovery() THEN 'replica' ELSE 'primary' END || ')';" \
        2>/dev/null || echo "CONNECT_FAILED")

    if [ "$RESULT" == "CONNECT_FAILED" ]; then
        fail "  ${SVC_SUFFIX} → connection failed"
    else
        ok "  ${SVC_SUFFIX} → $RESULT"
    fi
done

header "Client Connection Test Complete"
