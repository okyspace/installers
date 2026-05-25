#!/bin/bash
# ─── Run All HA Tests ───
# Usage: ./run-all.sh <cluster-name> [namespace]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLUSTER=${1:-postgres}
NS=${2:-postgres}

echo "═══════════════════════════════════════════"
echo "  CloudNativePG HA Test Suite"
echo "  Cluster : $CLUSTER"
echo "  Namespace: $NS"
echo "═══════════════════════════════════════════"
echo ""

TESTS=(
    "01-health-check.sh"
    "06-client-connection.sh"
    "02-write-continuity.sh"
    "03-failover-kill-primary.sh"
    "04-switchover.sh"
)

PASSED=0
FAILED=0

for TEST in "${TESTS[@]}"; do
    echo ""
    echo "▶ Running $TEST ..."
    echo "───────────────────────────────────────────"
    if "$SCRIPT_DIR/$TEST" "$CLUSTER" "$NS"; then
        PASSED=$((PASSED + 1))
    else
        FAILED=$((FAILED + 1))
        echo "  ⚠ $TEST exited with errors"
    fi
done

echo ""
echo "═══════════════════════════════════════════"
echo "  Results: $PASSED passed, $FAILED failed"
echo "═══════════════════════════════════════════"

[ "$FAILED" -eq 0 ] && exit 0 || exit 1
