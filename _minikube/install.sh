#!/usr/bin/env bash
# =============================================================================
#  _minikube/install.sh
#
#  Bootstraps a local Kubernetes cluster.  Edit config.env to adjust
#  CPU, RAM, versions, and IP ranges — no need to touch this file.
#
#  INFRA    │ Minikube cluster "general" — 2 nodes, subnet 192.168.100.0/24
#            │   all nodes  : CPUS / MEMORY from config.env (flat resource model)
#            │   images     : stored on VM disk (disk-size), not host mount
#            │                boltdb/mmap are incompatible with Docker volume mounts
#            │ Calico CNI     — NetworkPolicy enforcement, pod CIDR 10.244.0.0/16
#            │ MetalLB (L2)   — IP pool 192.168.100.11-192.168.100.20
#
#  PLATFORM │ NGINX Ingress Controller  @ 192.168.100.11  (core, always on)
#   optional│ cert-manager              — TLS certificate automation
#            │ KEDA                      — event-driven autoscaler
#            │ KGateway                  — Kubernetes Gateway API
#            │ Metrics Server            — kubectl top nodes/pods
#            │ kube-prometheus-stack     — Prometheus + Grafana (full stack)
#            │ Grafana                   — standalone Grafana dashboard
#            │ Local Path Provisioner    — default StorageClass
#
#  APPS     │ KAITO                     — LLM inference Workspace operator
#   optional│
#
#  Usage:
#    ./install.sh                  full install (infra + platform core)
#    ./install.sh remove           remove everything (reverse order)
#    ./install.sh <function>       call any install_* / remove_* directly
#    ./install.sh list             list all available functions
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Colours ───────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
info()    { echo -e "${CYAN}▶ $*${RESET}"; }
success() { echo -e "${GREEN}✔ $*${RESET}"; }
section() { echo -e "\n${YELLOW}══ $* ══${RESET}"; }

# =============================================================================
#  CONFIGURATION  —  sourced from config.env, overridable by env vars
# =============================================================================

# Load config.env (values there take effect unless already set in the shell)
if [[ -f "${SCRIPT_DIR}/config.env" ]]; then
  # export only unset variables — shell env takes precedence
  set -a
  # shellcheck source=config.env
  source <(grep -v '^\s*#' "${SCRIPT_DIR}/config.env" | grep -v '^\s*$')
  set +a
fi

# Fallback defaults (used when config.env is absent or a key is missing)
CLUSTER_NAME="${CLUSTER_NAME:-general}"
DRIVER="${DRIVER:-docker}"
SUBNET="${SUBNET:-192.168.100.0/24}"
K8S_VERSION="${K8S_VERSION:-v1.33.0}"

CPUS="${CPUS:-4}"
MEMORY="${MEMORY:-8192}"
ENABLE_GPU="${ENABLE_GPU:-false}"
CNI="${CNI:-auto}"

MOUNT_HOST="${MOUNT_HOST:-${SCRIPT_DIR}/data}"
MOUNT_VM="${MOUNT_VM:-/mnt/data}"
PV_STORE_VM="${MOUNT_VM}/pv"
PV_NAME="local-data"
PV_CAPACITY="${PV_CAPACITY:-20Gi}"

# INFRA
CALICO_NAMESPACE="kube-system"
CALICO_VERSION="${CALICO_VERSION:-v3.29.3}"
POD_CIDR="${POD_CIDR:-10.244.0.0/16}"

METALLB_NAMESPACE="metallb-system"
METALLB_VERSION="${METALLB_VERSION:-0.14.9}"
METALLB_IP_RANGE="${METALLB_IP_RANGE:-192.168.100.11-192.168.100.20}"

# PLATFORM
NGINX_NAMESPACE="ingress-nginx"
NGINX_VERSION="${NGINX_VERSION:-4.12.1}"
NGINX_LB_IP="${NGINX_LB_IP:-192.168.100.11}"

CERT_MANAGER_NAMESPACE="cert-manager"
CERT_MANAGER_VERSION="${CERT_MANAGER_VERSION:-v1.16.3}"

KEDA_NAMESPACE="keda"
KEDA_VERSION="${KEDA_VERSION:-2.16.1}"

KGATEWAY_NAMESPACE="kgateway-system"
KGATEWAY_VERSION="${KGATEWAY_VERSION:-2.0.3}"
GATEWAY_API_VERSION="${GATEWAY_API_VERSION:-v1.2.1}"
KGATEWAY_LB_IP="${KGATEWAY_LB_IP:-192.168.100.2}"

MONITORING_NAMESPACE="monitoring"
PROMETHEUS_VERSION="${PROMETHEUS_VERSION:-68.3.3}"

GRAFANA_NAMESPACE="grafana"
GRAFANA_VERSION="${GRAFANA_VERSION:-8.5.2}"

LOCALPATH_MANIFEST="https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.30/deploy/local-path-storage.yaml"

# APPS
KAITO_NAMESPACE="kaito-system"
KAITO_VERSION="${KAITO_VERSION:-0.7.2}"


# =============================================================================
#  INFRA — Minikube cluster
# =============================================================================

install_cluster() {
  section "INFRA │ Minikube Cluster '${CLUSTER_NAME}'"
  info "Nodes         : 2 × ${CPUS} CPU / ${MEMORY} MiB  (ENABLE_GPU=${ENABLE_GPU})"
  info "Host mount    : ${MOUNT_HOST} → ${MOUNT_VM}"
  info "PV data       : ${PV_STORE_VM}"

  mkdir -p "${MOUNT_HOST}/pv"

  local extra_flags=()
  [[ "${ENABLE_GPU}" == "true" ]] && extra_flags+=(--gpus all)

  # Step 1 — start cluster (new or stopped; minikube restores all existing nodes)
  local status
  status=$(minikube status --profile "${CLUSTER_NAME}" 2>/dev/null || true)
  if echo "${status}" | grep -q "apiserver: Running"; then
    success "Cluster '${CLUSTER_NAME}' already running — skipping start."
  else
    info "Starting cluster '${CLUSTER_NAME}'..."
    minikube start \
      --profile             "${CLUSTER_NAME}" \
      --driver              "${DRIVER}" \
      --subnet              "${SUBNET}" \
      --nodes               1 \
      --cpus                "${CPUS}" \
      --memory              "${MEMORY}" \
      --kubernetes-version  "${K8S_VERSION}" \
      --cni                 "${CNI}" \
      --mount \
      --mount-string        "${MOUNT_HOST}:${MOUNT_VM}" \
      "${extra_flags[@]}"

    kubectl config use-context "${CLUSTER_NAME}"
  fi

  # Step 2 — ensure exactly 2 nodes (add worker only if not already present)
  local node_count
  node_count=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  if [[ "${node_count}" -lt 2 ]]; then
    info "Adding worker node (currently ${node_count} node(s))..."
    minikube node add \
      --worker \
      --profile "${CLUSTER_NAME}"
  else
    info "Cluster already has ${node_count} node(s) — skipping node add."
  fi

  _label_gpu_node

  # Step 3 — StorageClass + PersistentVolume backed by data/pv/ inside the mounted folder
  info "Creating StorageClass and HostPath PersistentVolume '${PV_NAME}'..."
  kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${PV_NAME}
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: ${PV_NAME}
  labels:
    type: local
    cluster: ${CLUSTER_NAME}
spec:
  storageClassName: ${PV_NAME}
  capacity:
    storage: ${PV_CAPACITY}
  accessModes:
  - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: ${PV_STORE_VM}
    type: DirectoryOrCreate
EOF

  local node_ip
  node_ip=$(minikube ip --profile "${CLUSTER_NAME}")
  success "Cluster '${CLUSTER_NAME}' ready.  Control-plane IP: ${node_ip}"
  success "PV '${PV_NAME}': ${MOUNT_HOST}/pv (host) → ${PV_STORE_VM} (VM)  StorageClass: ${PV_NAME}"
  kubectl get nodes -o wide
}

# Label + taint the worker node as the GPU node
_label_gpu_node() {
  local worker
  worker=$(kubectl get nodes --no-headers | grep -v control-plane | awk '{print $1}' | head -1)
  [[ -z "${worker}" ]] && { info "No worker node — skipping GPU labels."; return; }
  info "Labelling '${worker}' as GPU worker..."
  kubectl label node "${worker}" \
    node-role.kubernetes.io/gpu="" \
    nvidia.com/gpu=present \
    kaito.sh/gpu-provisioner=false \
    accelerator=nvidia-gpu \
    --overwrite
  kubectl taint node "${worker}" \
    nvidia.com/gpu=present:NoSchedule \
    --overwrite 2>/dev/null || true
  success "Node '${worker}' labelled as GPU worker (taint: nvidia.com/gpu=present:NoSchedule)."
}

remove_cluster() {
  section "INFRA │ Remove Minikube Cluster '${CLUSTER_NAME}'"
  info "Deleting cluster (data folder preserved at ${MOUNT_HOST})..."
  minikube delete --profile "${CLUSTER_NAME}" 2>/dev/null || true
  success "Cluster deleted. Data at '${MOUNT_HOST}' untouched."
}


# =============================================================================
#  INFRA — Calico CNI
#  Provides pod networking and NetworkPolicy enforcement.
#  Cluster must be started with --cni none so Calico owns the CNI config.
# =============================================================================

install_calico() {
  section "INFRA │ Calico CNI ${CALICO_VERSION}"
  info "Pod CIDR: ${POD_CIDR}   Node subnet: ${SUBNET}"

  local manifest="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
  info "Applying Calico manifest..."
  curl -sL "${manifest}" \
    | sed "s|192\\.168\\.0\\.0/16|${POD_CIDR}|g" \
    | kubectl apply -f -

  # Calico auto-detects the wrong IP when a bridge interface is present; pin it
  # to the node subnet so BGP peers correctly across minikube's docker network.
  kubectl patch daemonset calico-node -n "${CALICO_NAMESPACE}" --type=json -p='[{
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {"name": "IP_AUTODETECTION_METHOD", "value": "cidr='"${SUBNET}"'"}
  }]'

  info "Waiting for calico-node DaemonSet to roll out (up to 3m)..."
  kubectl rollout status daemonset/calico-node -n "${CALICO_NAMESPACE}" --timeout=3m

  info "Waiting for all nodes to be Ready (up to 3m)..."
  kubectl wait node --all --for=condition=Ready --timeout=3m

  success "Calico ${CALICO_VERSION} ready."
  kubectl get nodes
}

remove_calico() {
  section "INFRA │ Remove Calico CNI"
  local manifest="https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
  curl -sL "${manifest}" | kubectl delete -f - 2>/dev/null || true
  kubectl get crd -o name 2>/dev/null \
    | grep -E 'projectcalico\.org|policy\.networking\.k8s\.io' \
    | xargs kubectl delete 2>/dev/null || true
  success "Calico removed."
}


# =============================================================================
#  INFRA — MetalLB  (Layer 2 load balancer)
# =============================================================================

install_metallb() {
  section "INFRA │ MetalLB ${METALLB_VERSION}"
  helm repo add metallb https://metallb.github.io/metallb --force-update
  helm upgrade --install metallb metallb/metallb \
    --namespace  "${METALLB_NAMESPACE}" \
    --create-namespace \
    --version    "${METALLB_VERSION}" \
    --wait --timeout 3m

  info "Applying IPAddressPool (${METALLB_IP_RANGE}) and L2Advertisement..."
  kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: general-pool
  namespace: ${METALLB_NAMESPACE}
spec:
  addresses:
  - ${METALLB_IP_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: general-l2
  namespace: ${METALLB_NAMESPACE}
spec:
  ipAddressPools:
  - general-pool
EOF
  success "MetalLB ready. Pool: ${METALLB_IP_RANGE}"
}

remove_metallb() {
  section "INFRA │ Remove MetalLB"
  kubectl delete -n "${METALLB_NAMESPACE}" ipaddresspool general-pool 2>/dev/null || true
  kubectl delete -n "${METALLB_NAMESPACE}" l2advertisement general-l2 2>/dev/null || true
  helm uninstall metallb --namespace "${METALLB_NAMESPACE}" 2>/dev/null || true
  kubectl delete namespace "${METALLB_NAMESPACE}" --ignore-not-found
  kubectl delete crd \
    ipaddresspools.metallb.io l2advertisements.metallb.io \
    bgppeers.metallb.io bgpadvertisements.metallb.io \
    communities.metallb.io bfdprofiles.metallb.io 2>/dev/null || true
  success "MetalLB removed."
}


# =============================================================================
#  PLATFORM — NGINX Ingress Controller  [core]
# =============================================================================

install_nginx_ingress() {
  section "PLATFORM │ NGINX Ingress Controller ${NGINX_VERSION}"
  info "LoadBalancer IP: ${NGINX_LB_IP}"
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace  "${NGINX_NAMESPACE}" \
    --create-namespace \
    --version    "${NGINX_VERSION}" \
    --set controller.service.type=LoadBalancer \
    --set controller.service.loadBalancerIP="${NGINX_LB_IP}" \
    --set controller.ingressClassResource.default=true \
    --set controller.ingressClassResource.name=nginx \
    --wait --timeout 3m
  success "NGINX Ingress ready."
  kubectl get svc -n "${NGINX_NAMESPACE}" ingress-nginx-controller \
    -o custom-columns='NAME:.metadata.name,TYPE:.spec.type,EXTERNAL-IP:.status.loadBalancer.ingress[0].ip,PORTS:.spec.ports[*].port'
}

remove_nginx_ingress() {
  section "PLATFORM │ Remove NGINX Ingress Controller"
  helm uninstall ingress-nginx --namespace "${NGINX_NAMESPACE}" 2>/dev/null || true
  kubectl delete namespace "${NGINX_NAMESPACE}" --ignore-not-found
  success "NGINX Ingress removed."
}


# =============================================================================
#  PLATFORM — cert-manager  [optional]
#  TLS certificate automation via Let's Encrypt or self-signed issuers.
# =============================================================================

install_cert_manager() {
  section "PLATFORM │ cert-manager ${CERT_MANAGER_VERSION}"
  helm repo add jetstack https://charts.jetstack.io --force-update
  helm upgrade --install cert-manager jetstack/cert-manager \
    --namespace  "${CERT_MANAGER_NAMESPACE}" \
    --create-namespace \
    --version    "${CERT_MANAGER_VERSION}" \
    --set installCRDs=true \
    --wait --timeout 5m
  success "cert-manager ready."
}

remove_cert_manager() {
  section "PLATFORM │ Remove cert-manager"
  helm uninstall cert-manager --namespace "${CERT_MANAGER_NAMESPACE}" 2>/dev/null || true
  kubectl delete namespace "${CERT_MANAGER_NAMESPACE}" --ignore-not-found
  kubectl delete crd \
    certificaterequests.cert-manager.io certificates.cert-manager.io \
    challenges.acme.cert-manager.io clusterissuers.cert-manager.io \
    issuers.cert-manager.io orders.acme.cert-manager.io 2>/dev/null || true
  success "cert-manager removed."
}


# =============================================================================
#  PLATFORM — KEDA  [optional]
#  Event-driven autoscaling — scales workloads on Kafka lag, queue depth, etc.
# =============================================================================

install_keda() {
  section "PLATFORM │ KEDA ${KEDA_VERSION}"
  helm repo add kedacore https://kedacore.github.io/charts --force-update
  helm upgrade --install keda kedacore/keda \
    --namespace  "${KEDA_NAMESPACE}" \
    --create-namespace \
    --version    "${KEDA_VERSION}" \
    --wait --timeout 5m
  success "KEDA ready. Define ScaledObject resources to autoscale Deployments."
}

remove_keda() {
  section "PLATFORM │ Remove KEDA"
  helm uninstall keda --namespace "${KEDA_NAMESPACE}" 2>/dev/null || true
  kubectl delete namespace "${KEDA_NAMESPACE}" --ignore-not-found
  kubectl delete crd \
    scaledobjects.keda.sh scaledjobs.keda.sh \
    triggerauthentications.keda.sh clustertriggerauthentications.keda.sh 2>/dev/null || true
  success "KEDA removed."
}


# =============================================================================
#  PLATFORM — KGateway  [optional]
#  Kubernetes Gateway API implementation. Install order: GW API CRDs → crds → controller.
#  Works alongside (or instead of) NGINX Ingress.
# =============================================================================

install_kgateway() {
  section "PLATFORM │ KGateway ${KGATEWAY_VERSION}"
  info "LoadBalancer IP: ${KGATEWAY_LB_IP}"

  info "Installing Gateway API CRDs (${GATEWAY_API_VERSION})..."
  kubectl apply -f \
    "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

  info "Installing kgateway CRDs..."
  helm upgrade --install kgateway-crds \
    oci://ghcr.io/kgateway-dev/helm-charts/kgateway-crds \
    --version "${KGATEWAY_VERSION}" --namespace "${KGATEWAY_NAMESPACE}" \
    --create-namespace --wait --timeout 3m

  info "Installing kgateway controller..."
  helm upgrade --install kgateway \
    oci://ghcr.io/kgateway-dev/helm-charts/kgateway \
    --version "${KGATEWAY_VERSION}" --namespace "${KGATEWAY_NAMESPACE}" \
    --wait --timeout 5m

  info "Reserving MetalLB IP ${KGATEWAY_LB_IP} for KGateway..."
  kubectl apply -f - <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: kgateway-pool
  namespace: ${METALLB_NAMESPACE}
spec:
  addresses:
  - ${KGATEWAY_LB_IP}/32
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: kgateway-l2
  namespace: ${METALLB_NAMESPACE}
spec:
  ipAddressPools:
  - kgateway-pool
EOF

  info "Creating default GatewayClass and Gateway (HTTP on ${KGATEWAY_LB_IP}:80)..."
  kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: kgateway
spec:
  controllerName: kgateway.dev/kgateway
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: default
  namespace: ${KGATEWAY_NAMESPACE}
  annotations:
    metallb.universe.tf/loadBalancerIPs: "${KGATEWAY_LB_IP}"
spec:
  gatewayClassName: kgateway
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    allowedRoutes:
      namespaces:
        from: All
EOF

  success "KGateway ready.  Gateway 'default' @ ${KGATEWAY_LB_IP}:80"
  echo "   Attach HTTPRoutes with: gatewayName: default  namespace: ${KGATEWAY_NAMESPACE}"
}

remove_kgateway() {
  section "PLATFORM │ Remove KGateway"
  kubectl delete gateway default -n "${KGATEWAY_NAMESPACE}" 2>/dev/null || true
  kubectl delete gatewayclass kgateway 2>/dev/null || true
  kubectl delete -n "${METALLB_NAMESPACE}" ipaddresspool kgateway-pool 2>/dev/null || true
  kubectl delete -n "${METALLB_NAMESPACE}" l2advertisement kgateway-l2 2>/dev/null || true
  helm uninstall kgateway      --namespace "${KGATEWAY_NAMESPACE}" 2>/dev/null || true
  helm uninstall kgateway-crds --namespace "${KGATEWAY_NAMESPACE}" 2>/dev/null || true
  kubectl delete namespace "${KGATEWAY_NAMESPACE}" --ignore-not-found
  kubectl delete crd \
    gateways.gateway.networking.k8s.io httproutes.gateway.networking.k8s.io \
    grpcroutes.gateway.networking.k8s.io referencegrants.gateway.networking.k8s.io \
    gatewayclasses.gateway.networking.k8s.io 2>/dev/null || true
  success "KGateway removed."
}


# =============================================================================
#  PLATFORM — Metrics Server  [optional]
#  Enables kubectl top nodes / kubectl top pods.
# =============================================================================

install_metrics_server() {
  section "PLATFORM │ Metrics Server"
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server --force-update
  helm upgrade --install metrics-server metrics-server/metrics-server \
    --namespace kube-system \
    --set args={--kubelet-insecure-tls} \
    --wait --timeout 3m
  success "Metrics Server ready. Try: kubectl top nodes"
}

remove_metrics_server() {
  section "PLATFORM │ Remove Metrics Server"
  helm uninstall metrics-server --namespace kube-system 2>/dev/null || true
  success "Metrics Server removed."
}


# =============================================================================
#  PLATFORM — kube-prometheus-stack  [optional]
#  Prometheus + Grafana + Alertmanager.
#  Access Grafana: kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
#  Login: admin / prom-operator
# =============================================================================

install_monitoring() {
  section "PLATFORM │ kube-prometheus-stack ${PROMETHEUS_VERSION}"
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace  "${MONITORING_NAMESPACE}" \
    --create-namespace \
    --version    "${PROMETHEUS_VERSION}" \
    --set grafana.service.type=ClusterIP \
    --set prometheus.prometheusSpec.retention=7d \
    --wait --timeout 10m
  success "Monitoring stack ready."
  echo "   Grafana: kubectl -n ${MONITORING_NAMESPACE} port-forward svc/kube-prometheus-stack-grafana 3000:80"
  echo "   Login:   admin / prom-operator"
}

remove_monitoring() {
  section "PLATFORM │ Remove Monitoring Stack"
  helm uninstall kube-prometheus-stack --namespace "${MONITORING_NAMESPACE}" 2>/dev/null || true
  kubectl delete namespace "${MONITORING_NAMESPACE}" --ignore-not-found
  kubectl delete crd \
    alertmanagerconfigs.monitoring.coreos.com alertmanagers.monitoring.coreos.com \
    podmonitors.monitoring.coreos.com probes.monitoring.coreos.com \
    prometheusagents.monitoring.coreos.com prometheuses.monitoring.coreos.com \
    prometheusrules.monitoring.coreos.com scrapeconfigs.monitoring.coreos.com \
    servicemonitors.monitoring.coreos.com thanosrulers.monitoring.coreos.com 2>/dev/null || true
  success "Monitoring stack removed."
}


# =============================================================================
#  PLATFORM — Grafana  [optional]
#  Standalone Grafana dashboard (no Prometheus bundled).
#  Access: kubectl -n grafana port-forward svc/grafana 3000:80
#  Login: admin / admin  (change via grafana.adminPassword below)
# =============================================================================

install_grafana() {
  section "PLATFORM │ Grafana ${GRAFANA_VERSION}"
  helm repo add grafana https://grafana.github.io/helm-charts --force-update
  helm upgrade --install grafana grafana/grafana \
    --namespace  "${GRAFANA_NAMESPACE}" \
    --create-namespace \
    --version    "${GRAFANA_VERSION}" \
    --set adminPassword=admin \
    --set service.type=LoadBalancer \
    --wait --timeout 5m
  success "Grafana ready."
  local lb_ip
  lb_ip=$(kubectl get svc -n "${GRAFANA_NAMESPACE}" grafana \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "pending")
  echo "   URL:   http://${lb_ip}:80  (or port-forward: kubectl -n ${GRAFANA_NAMESPACE} port-forward svc/grafana 3000:80)"
  echo "   Login: admin / admin"
}

remove_grafana() {
  section "PLATFORM │ Remove Grafana"
  helm uninstall grafana --namespace "${GRAFANA_NAMESPACE}" 2>/dev/null || true
  kubectl delete namespace "${GRAFANA_NAMESPACE}" --ignore-not-found
  success "Grafana removed."
}


# =============================================================================
#  PLATFORM — Local Path Provisioner  [optional]
#  Lightweight default StorageClass (local-path) for dev PVCs.
# =============================================================================

install_local_path() {
  section "PLATFORM │ Local Path Provisioner"
  kubectl apply -f "${LOCALPATH_MANIFEST}"
  kubectl patch storageclass local-path \
    -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
  success "Local Path Provisioner ready. Default StorageClass: local-path"
}

remove_local_path() {
  section "PLATFORM │ Remove Local Path Provisioner"
  kubectl delete -f "${LOCALPATH_MANIFEST}" 2>/dev/null || true
  success "Local Path Provisioner removed."
}


# =============================================================================
#  APPS — KAITO  [optional]
#  Kubernetes AI Toolchain Operator — manages LLM inference via Workspace CRDs.
#  Nodes must be pre-labelled (done by install_cluster). No cloud GPU provisioner.
# =============================================================================

install_kaito() {
  section "APPS │ KAITO ${KAITO_VERSION}"
  helm repo add kaito https://kaito-project.github.io/kaito --force-update
  helm upgrade --install kaito-workspace kaito/workspace \
    --namespace  "${KAITO_NAMESPACE}" \
    --create-namespace \
    --version    "${KAITO_VERSION}" \
    --set controller.disableNodeAutoProvisioning=true \
    --set controller.featureGates.localCSIDriver=false \
    --set controller.featureGates.gatewayAPIInferenceExtension=false \
    --wait --timeout 5m
  success "KAITO ready. Apply a Workspace CR to deploy a model."
  echo "   Docs: https://github.com/kaito-project/kaito/tree/main/docs"
}

remove_kaito() {
  section "APPS │ Remove KAITO"
  helm uninstall kaito-workspace --namespace "${KAITO_NAMESPACE}" 2>/dev/null || true
  kubectl delete namespace "${KAITO_NAMESPACE}" --ignore-not-found
  kubectl delete crd \
    workspaces.kaito.sh ragengines.kaito.sh \
    inferencepools.inference.networking.x-k8s.io 2>/dev/null || true
  success "KAITO removed."
}


# =============================================================================
#  REMOVE TIERS
# =============================================================================

remove_apps() {
  section "Removing all APPS"
  remove_kaito
}

remove_platform() {
  section "Removing all PLATFORM components"
  remove_local_path
  remove_grafana
  remove_monitoring
  remove_metrics_server
  remove_kgateway
  remove_keda
  remove_cert_manager
  remove_nginx_ingress
}

remove_infra() {
  section "Removing all INFRA"
  remove_metallb
  remove_calico
  remove_cluster
}

remove_all() {
  remove_apps
  remove_platform
  remove_infra
  success "All components removed."
}


# =============================================================================
#  MAIN  —  uncomment optional components to include them in the default install
# =============================================================================

main() {
  echo -e "${YELLOW}"
  echo "  Cluster : ${CLUSTER_NAME}   Driver: ${DRIVER}"
  echo "  Nodes   : 2 × ${CPUS} CPU / ${MEMORY} MiB   GPU: ${ENABLE_GPU}"
  echo -e "${RESET}"

  # ── INFRA ────────────────────────────────────────────────────────────────
  install_cluster
  install_calico
  install_metallb

  # ── PLATFORM (core) ───────────────────────────────────────────────────────
  install_nginx_ingress

  # ── PLATFORM (optional — uncomment to enable) ─────────────────────────────
  # install_cert_manager      # TLS automation
  # install_keda              # event-driven autoscaler
  # install_kgateway          # Gateway API (alternative ingress)
  # install_metrics_server    # kubectl top nodes/pods
  # install_monitoring        # Prometheus + Grafana (full stack)
  # install_grafana           # standalone Grafana dashboard
  # install_local_path        # default StorageClass for PVCs

  # ── APPS (optional — uncomment to enable) ────────────────────────────────
  # install_kaito             # LLM inference Workspace operator

  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${GREEN}║  ${CLUSTER_NAME} is ready                                        ${RESET}"
  echo -e "${GREEN}║  NGINX Ingress  →  ${NGINX_LB_IP}                     ${RESET}"
  echo -e "${GREEN}║  MetalLB pool   →  ${METALLB_IP_RANGE}          ${RESET}"
  echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
}


# =============================================================================
#  ENTRY POINT
# =============================================================================

CMD="${1:-main}"
case "${CMD}" in
  main|install)       main ;;
  remove|uninstall)   remove_all ;;
  remove_infra)       remove_infra ;;
  remove_platform)    remove_platform ;;
  remove_apps)        remove_apps ;;
  list)
    echo "Available functions:"
    declare -F | awk '{print "  " $3}' | grep -E '^  (install|remove)_' | sort
    ;;
  *)
    if declare -f "${CMD}" > /dev/null 2>&1; then
      "${CMD}"
    else
      echo "Unknown command: ${CMD}"
      echo "Run './install.sh list' to see all available functions."
      exit 1
    fi
    ;;
esac
