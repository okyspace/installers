# CloudNativePG

PostgreSQL HA on Kubernetes via the CloudNativePG operator (originally created and sponsored by EDB).

| Chart | Version |
|---|---|
| `cnpg/cloudnative-pg` (operator) | 0.28.2 |
| `cnpg/cluster` (database cluster) | 0.6.1 |

**References**
- [GitHub — cloudnative-pg/cloudnative-pg](https://github.com/cloudnative-pg/cloudnative-pg)
- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/current/)
- [Helm Charts — cloudnative-pg/charts](https://github.com/cloudnative-pg/charts)

---

## Components

### Operator (`cnpg/cloudnative-pg`)

Runs as a Deployment in `cnpg-system`. Watches for `Cluster` CRDs across the entire cluster and reconciles them into running PostgreSQL pods. **Install once per Kubernetes cluster** — it manages all database instances across all namespaces.

Configured via `override-operator.yaml`.

### Cluster (`cnpg/cluster`)

Deploys a PostgreSQL `Cluster` CR — the actual database workload. **Every namespace that needs a PostgreSQL instance requires its own cluster installation.** The operator watches for these CRs and provisions the pods, services, and streaming replication automatically.

Configured via `override-cluster.yaml`. Key defaults:

| Setting | Default | Description |
|---|---|---|
| `cluster.instances` | `3` | Primary + 2 replicas (HA) |
| `cluster.storage.size` | `10Gi` | PVC size per instance |
| `cluster.postgresql.parameters.max_connections` | `200` | Max client connections |
| `cluster.postgresql.parameters.shared_buffers` | `256MB` | Postgres shared memory |

---

## Install

```bash
# Download charts and images (run once, or to upgrade versions)
./download.sh
```

```bash
# Install operator + cluster (cluster goes into 'postgres' namespace by default)
./install.sh

# Install operator + cluster into a specific namespace
./install.sh all <namespace>

# Install operator only (once per cluster)
./install.sh operator

# Install a cluster into a specific namespace (operator must already be running)
./install.sh cluster <namespace>
```

**Example — two separate app namespaces each with their own Postgres:**
```bash
./install.sh operator
./install.sh cluster app-alpha
./install.sh cluster app-beta
```

---

## Uninstall

```bash
# Remove a cluster from a namespace
helm uninstall postgres -n <namespace>

# Remove the operator (only after all clusters are removed)
helm uninstall cloudnative-pg -n cnpg-system
```

> Uninstalling the cluster chart does **not** delete the PVCs. Delete them manually if you want to reclaim storage.
