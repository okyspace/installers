#!/usr/bin/env bash
# =============================================================================
#  _minikube/uninstall.sh
#
#  Removes components installed by install.sh.
#  Sources install.sh so all remove_* functions are available.
#
#  Usage:
#    ./uninstall.sh                 remove everything (apps → platform → infra)
#    ./uninstall.sh apps            remove all APPS tier only
#    ./uninstall.sh platform        remove all PLATFORM tier only
#    ./uninstall.sh infra           remove MetalLB + cluster (data/ preserved)
#
#    Individual components:
#    ./uninstall.sh cluster
#    ./uninstall.sh metallb
#    ./uninstall.sh nginx_ingress
#    ./uninstall.sh cert_manager
#    ./uninstall.sh keda
#    ./uninstall.sh kgateway
#    ./uninstall.sh metrics_server
#    ./uninstall.sh monitoring
#    ./uninstall.sh local_path
#    ./uninstall.sh kaito
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install.sh
source "${SCRIPT_DIR}/install.sh"

CMD="${1:-all}"

case "${CMD}" in
  # ── Tiers ────────────────────────────────────────────────────────────────
  all|uninstall)   remove_all ;;
  apps)            remove_apps ;;
  platform)        remove_platform ;;
  infra)           remove_infra ;;

  # ── INFRA ────────────────────────────────────────────────────────────────
  cluster)         remove_cluster ;;
  metallb)         remove_metallb ;;

  # ── PLATFORM ─────────────────────────────────────────────────────────────
  nginx_ingress)   remove_nginx_ingress ;;
  cert_manager)    remove_cert_manager ;;
  keda)            remove_keda ;;
  kgateway)        remove_kgateway ;;
  metrics_server)  remove_metrics_server ;;
  monitoring)      remove_monitoring ;;
  grafana)         remove_grafana ;;
  local_path)      remove_local_path ;;

  # ── APPS ─────────────────────────────────────────────────────────────────
  kaito)           remove_kaito ;;

  *)
    echo "Unknown component: ${CMD}"
    echo ""
    echo "Usage: $0 [target]"
    echo ""
    echo "Tiers (removes all components in that tier):"
    echo "  (none) / all    apps → platform → infra → cluster"
    echo "  apps            remove all APPS"
    echo "  platform        remove all PLATFORM components"
    echo "  infra           remove MetalLB + cluster (data/ folder preserved)"
    echo ""
    echo "INFRA:"
    echo "  cluster         delete the minikube cluster"
    echo "  metallb         MetalLB + CRDs"
    echo ""
    echo "PLATFORM:"
    echo "  nginx_ingress   NGINX Ingress Controller"
    echo "  cert_manager    cert-manager + CRDs"
    echo "  keda            KEDA + CRDs"
    echo "  kgateway        KGateway + Gateway API CRDs"
    echo "  metrics_server  Metrics Server"
    echo "  monitoring      Prometheus + Grafana (full stack) + CRDs"
    echo "  grafana         Standalone Grafana"
    echo "  local_path      Local Path Provisioner"
    echo ""
    echo "APPS:"
    echo "  kaito           KAITO Workspace operator + CRDs"
    exit 1
    ;;
esac
