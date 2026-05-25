# CloudNativePG — HA Test Suite

Validates high-availability behavior of the CloudNativePG cluster deployed via the parent Helm chart.

## Prerequisites

| Requirement | Purpose |
|---|---|
| Running CloudNativePG operator | `../install.sh operator` |
| Running Cluster (≥ 3 instances) | `../install.sh cluster <ns>` |
| `kubectl cnpg` plugin | Status checks, pgbench, promote |

Install the `kubectl cnpg` plugin:
```bash
# Via krew
kubectl krew install cnpg

# Or download binary directly
# https://github.com/cloudnative-pg/cloudnative-pg/releases
```

---

## Tests

### 1. Cluster Health Check (`01-health-check.sh`)

Verifies the cluster is running with the expected number of instances and all replicas are streaming.

```bash
./01-health-check.sh <cluster-name> [namespace]
```

### 2. Write Continuity (`02-write-continuity.sh`)

Inserts rows in a loop and reports gaps after a failover event. Run this **in parallel** with a failover test to measure data loss / downtime window.

```bash
./02-write-continuity.sh <cluster-name> [namespace]
```

### 3. Failover — Kill Primary (`03-failover-kill-primary.sh`)

Deletes the current primary pod and watches the operator elect a new primary. Reports:
- Time to detect failure
- Time to promote new primary
- Whether the old primary rejoins as a replica

```bash
./03-failover-kill-primary.sh <cluster-name> [namespace]
```

### 4. Switchover — Planned Promotion (`04-switchover.sh`)

Triggers a graceful switchover to a chosen replica. Useful for testing maintenance scenarios.

```bash
./04-switchover.sh <cluster-name> [namespace]
```

### 5. pgbench Stress Under Failover (`05-pgbench-failover.sh`)

Runs a pgbench workload, kills the primary mid-run, and reports TPS impact.

```bash
./05-pgbench-failover.sh <cluster-name> [namespace]
```

### 6. Client Connection Test (`06-client-connection.sh`)

Deploys a psql client pod and verifies connectivity through the `-rw`, `-ro`, and `-r` services.

```bash
./06-client-connection.sh <cluster-name> [namespace]
```

---

## Quick Run

```bash
# Run all tests sequentially against a cluster named 'postgres' in namespace 'postgres'
./run-all.sh postgres postgres
```
