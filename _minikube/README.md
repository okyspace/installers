# Local Kubernetes Cluster

Edit **`config.env`** to adjust CPU, RAM, IP ranges, and versions — then run `install.sh`. No other file needs to change.

---

## Configuration — `config.env`

| Setting | Default | Description |
|---|---|---|
| `CLUSTER_NAME` | `general` | Minikube profile name |
| `DRIVER` | `docker` | `docker` \| `kvm2` \| `virtualbox` |
| `SUBNET` | `192.168.100.0/24` | Node network subnet |
| `K8S_VERSION` | `v1.35.0` | Kubernetes version |
| `CPUS` | `4` | CPUs per node — applies to all nodes (minikube flat model) |
| `MEMORY` | `8192` | RAM per node in MiB — applies to all nodes |
| `ENABLE_GPU` | `false` | `true` requires `nvidia-container-toolkit` on the host |
| `METALLB_IP_RANGE` | `192.168.100.11-192.168.100.20` | LoadBalancer IP pool |
| `NGINX_LB_IP` | `192.168.100.11` | Fixed IP for NGINX Ingress |
| `KGATEWAY_LB_IP` | `192.168.100.2` | Fixed IP for KGateway default Gateway |
| `PV_CAPACITY` | `60Gi` | Size of the shared PersistentVolume |

> **Flat resource model:** minikube applies `CPUS` and `MEMORY` uniformly to every node. Per-node overrides are not supported.

All other settings (chart versions, namespaces) are also in `config.env`.

---

## INFRA

Always installed. Foundation everything else runs on.

| Component | Details |
|---|---|
| **Minikube cluster** | 2 nodes — control-plane + GPU worker (same CPUS/MEMORY, worker is labelled + tainted for GPU) |
| **Host mount** | `data/pv/` (host) → `/mnt/data/pv` (VM) — backing store for the PersistentVolume; containerd images stay on the VM's own disk |
| **MetalLB** | L2 mode, pool `192.168.100.11–192.168.100.20` |

---

## PLATFORM

Core platform services. NGINX Ingress is installed by default; the rest are optional.

| Component | Default | Description |
|---|---|---|
| **NGINX Ingress** | ✅ on | LoadBalancer @ `192.168.100.11`. Default IngressClass. |
| **cert-manager** | off | Automatic TLS via Let's Encrypt or self-signed CAs |
| **KEDA** | off | Event-driven autoscaler — Kafka lag, queue depth, custom metrics |
| **KGateway** | off | Gateway API implementation. Default Gateway @ `192.168.100.2:80`. Alternative to NGINX Ingress. |
| **Metrics Server** | off | Enables `kubectl top nodes` / `kubectl top pods` |
| **kube-prometheus-stack** | off | Prometheus + Grafana (full stack). Port-forward: `kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80` · login: `admin / prom-operator` |
| **Grafana** | off | Standalone Grafana dashboard. LoadBalancer IP from MetalLB pool · login: `admin / admin` |
| **Local Path Provisioner** | off | Sets `local-path` as default StorageClass for dev PVCs |

---

## APPS

AI/ML operators. All optional — uncomment in `main()` in `install.sh` to enable on every install.

| Component | Default | Description |
|---|---|---|
| **KAITO** | off | Kubernetes AI Toolchain Operator. Manages LLM inference via Workspace CRDs. Worker node is pre-labelled by the cluster install. |

---

## Install

```bash
# Full install (infra + platform core)
./install.sh

# Add an optional component after the cluster is running
./install.sh install_cert_manager
./install.sh install_keda
./install.sh install_monitoring
./install.sh install_grafana
./install.sh install_kaito

# See all available functions
./install.sh list
```

---

## Uninstall

```bash
# Remove everything, top to bottom
./install.sh remove

# Remove by tier (cluster stays up when removing platform/apps)
./install.sh remove_apps
./install.sh remove_platform
./install.sh remove_infra

# Remove a single component
./install.sh remove_kaito
./install.sh remove_keda
./install.sh remove_cert_manager
./install.sh remove_grafana
./install.sh remove_nginx_ingress
./install.sh remove_metallb
./install.sh remove_cluster
```

> The `data/` folder is **never deleted** by uninstall. Recreating the cluster reconnects to the same PV data.
