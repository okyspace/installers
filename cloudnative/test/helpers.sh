#!/bin/bash
# ─── Shared helpers for CloudNativePG HA tests ───

set -euo pipefail

# ──────────────────────────────────────────────
# Globals (set by parse_args)
# ──────────────────────────────────────────────
CLUSTER_NAME=""
NAMESPACE=""

# ──────────────────────────────────────────────
# Usage / arg parsing
# ──────────────────────────────────────────────
parse_args() {
    local script_name=$1; shift
    if [ $# -lt 1 ]; then
        echo "Usage: $script_name <cluster-name> [namespace]"
        exit 1
    fi
    CLUSTER_NAME=$1
    NAMESPACE=${2:-postgres}
}

# ──────────────────────────────────────────────
# Colours
# ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Colour

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[PASS]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; }
header() { echo -e "\n${BOLD}═══ $* ═══${NC}\n"; }

# ──────────────────────────────────────────────
# Cluster helpers
# ──────────────────────────────────────────────

# Get the name of the current primary pod
get_primary_pod() {
    kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.status.currentPrimary}'
}

# Get names of replica pods (everything that is NOT the primary)
get_replica_pods() {
    local primary
    primary=$(get_primary_pod)
    kubectl get pods -n "$NAMESPACE" \
        -l "cnpg.io/cluster=$CLUSTER_NAME" \
        -o jsonpath='{.items[*].metadata.name}' | tr ' ' '\n' | grep -v "$primary"
}

# Get the number of ready instances reported by the cluster status
get_ready_instances() {
    kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.status.readyInstances}'
}

# Get the target instance count from the spec
get_target_instances() {
    kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.spec.instances}'
}

# Get the rw service name (primary endpoint)
get_rw_service() {
    echo "${CLUSTER_NAME}-rw"
}

# Get the ro service name (read-only replicas endpoint)
get_ro_service() {
    echo "${CLUSTER_NAME}-ro"
}

# Get the r service name (any instance endpoint)
get_r_service() {
    echo "${CLUSTER_NAME}-r"
}

# Get the database superuser secret name
get_superuser_secret() {
    kubectl get cluster "$CLUSTER_NAME" -n "$NAMESPACE" \
        -o jsonpath='{.status.secretsResourceVersion.superuserSecretName}' 2>/dev/null || \
    echo "${CLUSTER_NAME}-superuser"
}

# Decode the superuser password from the secret
get_superuser_password() {
    local secret_name
    secret_name=$(get_superuser_secret)
    kubectl get secret "$secret_name" -n "$NAMESPACE" \
        -o jsonpath='{.data.password}' | base64 -d
}

# Wait for the cluster to reach the expected number of ready instances
# Usage: wait_for_ready [timeout_seconds]
wait_for_ready() {
    local timeout=${1:-120}
    local target
    target=$(get_target_instances)
    info "Waiting up to ${timeout}s for ${target} instances to be ready..."

    local elapsed=0
    while [ "$elapsed" -lt "$timeout" ]; do
        local ready
        ready=$(get_ready_instances 2>/dev/null || echo 0)
        if [ "$ready" == "$target" ]; then
            ok "All ${target} instances ready (took ${elapsed}s)"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    fail "Timed out waiting for cluster to be ready (${elapsed}s elapsed, wanted ${target} instances)"
    return 1
}

# Wait for a specific pod to be Running and Ready
# Usage: wait_for_pod <pod-name> [timeout_seconds]
wait_for_pod() {
    local pod=$1
    local timeout=${2:-120}
    info "Waiting up to ${timeout}s for pod ${pod} to be ready..."

    if kubectl wait pod "$pod" -n "$NAMESPACE" \
        --for=condition=Ready --timeout="${timeout}s" 2>/dev/null; then
        ok "Pod ${pod} is ready"
        return 0
    else
        fail "Pod ${pod} did not become ready within ${timeout}s"
        return 1
    fi
}

# Timestamp in epoch seconds (portable)
now_epoch() {
    date +%s
}
