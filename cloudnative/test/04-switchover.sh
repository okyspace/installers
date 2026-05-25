#!/bin/bash
# ─── Test 04: Switchover — Planned Promotion ───
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"
parse_args "$0" "$@"
TARGET_POD=${3:-}

header "Switchover Test (${CLUSTER_NAME}, ns: ${NAMESPACE})"

wait_for_ready 60
OLD_PRIMARY=$(get_primary_pod)
ok "Current primary: $OLD_PRIMARY"

if [ -z "$TARGET_POD" ]; then
    TARGET_POD=$(get_replica_pods | head -n 1)
fi
if [ -z "$TARGET_POD" ]; then
    fail "No replica pods available"; exit 1
fi
ok "Target replica: $TARGET_POD"

info "Triggering switchover: $OLD_PRIMARY → $TARGET_POD"
SWITCH_EPOCH=$(now_epoch)

if kubectl cnpg version &>/dev/null 2>&1; then
    kubectl cnpg promote "$CLUSTER_NAME" "$TARGET_POD" -n "$NAMESPACE"
else
    info "cnpg plugin not found — using kubectl patch"
    kubectl patch cluster "$CLUSTER_NAME" -n "$NAMESPACE" --type merge \
        -p "{\"spec\":{\"primaryUpdateStrategy\":\"unsupervised\"}}"
fi

info "Waiting for $TARGET_POD to become primary..."
TIMEOUT=120; ELAPSED=0; DONE_EPOCH=""
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
    CUR=$(get_primary_pod 2>/dev/null || echo "")
    if [ "$CUR" == "$TARGET_POD" ]; then DONE_EPOCH=$(now_epoch); break; fi
    sleep 1; ELAPSED=$((ELAPSED + 1))
done

if [ -z "$DONE_EPOCH" ]; then
    fail "Switchover did not complete within ${TIMEOUT}s"; exit 1
fi
SWITCH_TIME=$((DONE_EPOCH - SWITCH_EPOCH))
ok "Switchover complete in ${SWITCH_TIME}s"

sleep 5
wait_for_ready 60

header "Switchover Summary"
echo "  Old primary     : $OLD_PRIMARY"
echo "  New primary     : $TARGET_POD"
echo "  Switchover time : ${SWITCH_TIME}s"
header "Switchover Test Complete"
