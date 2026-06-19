#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="demo"
PROXY_LOCAL_PORT="8090"
HOST_HEADER="sample-app.example.com"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
info()    { echo -e "${CYAN}▶ $*${RESET}"; }
success() { echo -e "${GREEN}✔ $*${RESET}"; }
section() { echo -e "\n${YELLOW}══ $* ══${RESET}"; }

# =============================================================================
#  INSTALL
# =============================================================================

install() {
  section "Creating namespace '${NAMESPACE}'"
  kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

  section "Deploying sample app"
  kubectl apply -f "${SCRIPT_DIR}/01-sample-app.yaml"
  kubectl rollout status deployment/sample-app -n "${NAMESPACE}" --timeout=2m
  success "sample-app running"

  section "Creating InterceptorRoute"
  kubectl apply -f "${SCRIPT_DIR}/02-interceptorroute.yaml"
  kubectl get interceptorroute -n "${NAMESPACE}"

  section "Creating ScaledObject"
  kubectl apply -f "${SCRIPT_DIR}/03-scaledobject.yaml"
  kubectl get scaledobject -n "${NAMESPACE}"

  success "Install complete. Run: $0 test"
}

# =============================================================================
#  TEST — single request
# =============================================================================

test_single() {
  section "Single request test"
  info "Port-forwarding interceptor proxy → localhost:${PROXY_LOCAL_PORT} (background)"
  kubectl port-forward -n keda svc/keda-add-ons-http-interceptor-proxy \
    "${PROXY_LOCAL_PORT}:8080" &
  PF_PID=$!
  sleep 2

  info "Sending request via interceptor..."
  curl -s -H "Host: ${HOST_HEADER}" "localhost:${PROXY_LOCAL_PORT}"
  echo ""

  kill "${PF_PID}" 2>/dev/null || true
  success "Single request done"
}

# =============================================================================
#  TEST — load burst (triggers scale-up)
# =============================================================================

test_load() {
  section "Load burst test (300 requests → should trigger scale-up)"
  info "Port-forwarding interceptor proxy → localhost:${PROXY_LOCAL_PORT} (background)"
  kubectl port-forward -n keda svc/keda-add-ons-http-interceptor-proxy \
    "${PROXY_LOCAL_PORT}:8080" &
  PF_PID=$!
  sleep 2

  info "Watching deployment replicas in background..."
  kubectl get deployment sample-app -n "${NAMESPACE}" -w &
  WATCH_PID=$!

  info "Sending 300 requests..."
  for i in $(seq 1 300); do
    curl -s -H "Host: ${HOST_HEADER}" "localhost:${PROXY_LOCAL_PORT}/?wait=50ms" > /dev/null
  done

  info "Waiting 15s for scale-up to be visible..."
  sleep 15
  kubectl get deployment sample-app -n "${NAMESPACE}"

  kill "${PF_PID}" "${WATCH_PID}" 2>/dev/null || true
  success "Load test done. Check replicas above — should be > 1."
}

# =============================================================================
#  STATUS
# =============================================================================

status() {
  section "KEDA HTTP Add-on status"
  kubectl get pods -n keda
  echo ""
  kubectl get interceptorroute,scaledobject,deployment -n "${NAMESPACE}" 2>/dev/null || true
}

# =============================================================================
#  CLEANUP
# =============================================================================

cleanup() {
  section "Removing namespace '${NAMESPACE}'"
  kubectl delete namespace "${NAMESPACE}" --ignore-not-found
  success "Cleaned up."
}

# =============================================================================
#  ENTRY POINT
# =============================================================================

CMD="${1:-help}"
case "${CMD}" in
  install)      install ;;
  test)         test_single ;;
  test-load)    test_load ;;
  status)       status ;;
  cleanup)      cleanup ;;
  *)
    echo "Usage: $0 <command>"
    echo ""
    echo "  install     deploy sample-app, InterceptorRoute, ScaledObject"
    echo "  test        send a single request through the interceptor"
    echo "  test-load   send 300 requests to trigger scale-up"
    echo "  status      show pods and KEDA resources"
    echo "  cleanup     delete the demo namespace"
    ;;
esac
