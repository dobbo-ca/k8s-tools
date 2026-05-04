# k8s-tools

Diagnostic container images for Kubernetes. Drop a pod into your cluster,
`kubectl exec` in, and reach for any of dozens of network/TLS/HTTP/DB tools
without having to remember the right Alpine package name at 3 AM.

Built on Chainguard Wolfi for a small, regularly-patched base. Multi-arch
(amd64 + arm64). Published weekly to ghcr.io.

---

## Images

```
ghcr.io/dobbo-ca/k8s-tools:full-latest
ghcr.io/dobbo-ca/k8s-tools:postgres-pg15-latest
ghcr.io/dobbo-ca/k8s-tools:postgres-pg16-latest
ghcr.io/dobbo-ca/k8s-tools:postgres-pg17-latest
```

| Variant | Includes |
|---|---|
| `full` | DNS (dig, drill), TLS (openssl, sslscan, testssl), HTTP (curl, wget, nmap), network (mtr, traceroute, ping), sockets (nc, ss), tracing (tcpdump, strace), bandwidth (iperf3), JSON/YAML (jq, yq), editor (nvim) |
| `postgres-pg{15,16,17}` | Everything in `full` plus psql, pg_dump, pg_restore, pgbench, pgBackRest, WAL-G, pgCenter, pgBadger |

### Tag scheme (CalVer)

For each variant:
- `<variant>-latest` — most recent build
- `<variant>-YYYY.MM.DD` — daily-resolution tag
- `<variant>-YYYY.MM.DD-<sha7>` — fully pinned

Use `latest` for ephemeral debug pods; pin to a dated tag for anything
declarative (Helm values, Argo manifests).

---

## Quick start

```bash
# Drop a debug pod into the cluster
kubectl run k8s-tools --image=ghcr.io/dobbo-ca/k8s-tools:full-latest \
  --restart=Never --rm -it --command -- bash

# Or as a long-running pod
kubectl run k8s-tools --image=ghcr.io/dobbo-ca/k8s-tools:full-latest
kubectl exec -it k8s-tools -- bash
```

For Postgres debugging:

```bash
kubectl run pg-debug --image=ghcr.io/dobbo-ca/k8s-tools:postgres-pg17-latest
kubectl exec -it pg-debug -- bash
# inside:
psql -h my-db.svc.cluster.local -U postgres -d app
```

See [TOOLS.md](TOOLS.md) for the full tool list with examples.

---

## Helm chart

```bash
helm install diag charts/k8s-tools/
```

Key values (see [`charts/k8s-tools/values.yaml`](charts/k8s-tools/values.yaml)):

| Value | Default | Description |
|---|---|---|
| `variant` | `full` | `full` or `postgres` |
| `postgres.version` | `"17"` | PG major version (15/16/17), only used when `variant=postgres` |
| `image.tag` | `""` | Override; leave empty to auto-resolve from variant |
| `persistence.enabled` | `false` | If true, deploys as StatefulSet with PVC mounted at `/data` |
| `persistence.size` | `10Gi` | PVC size |

### Postgres debug with persistence (e.g., for capturing big dumps)

```bash
helm install pg-debug charts/k8s-tools/ \
  --set variant=postgres \
  --set postgres.version=17 \
  --set persistence.enabled=true \
  --set persistence.size=50Gi
```

---

## Security posture

- Runs as non-root (`nobody`, UID 65534)
- Read-only root filesystem by default; `/tmp` is the only writable path
- All capabilities dropped, `allowPrivilegeEscalation: false`
- `seccompProfile: RuntimeDefault`
- SUID/SGID bits stripped from all binaries during build
- Trivy scans on every PR; CRITICAL/HIGH CVEs block merge
- Weekly rebuild picks up upstream Wolfi patches

---

## Building locally

```bash
# Full image
docker buildx build -f containers/full/Dockerfile -t k8s-tools:full-local .

# Postgres image (depends on full)
docker buildx build -f containers/postgres/Dockerfile \
  --build-arg PG_MAJOR=17 \
  --build-arg FULL_IMAGE=k8s-tools:full-local \
  -t k8s-tools:postgres-pg17-local .
```

---

## Contributing

1. Open a PR — the CI workflow builds every variant and runs Trivy.
2. CRITICAL/HIGH CVEs are a blocker; bump the offending package or wait for
   the next Wolfi sync if the fix is upstream.
3. New tools go in `containers/full/Dockerfile` if they're general-purpose,
   `containers/postgres/Dockerfile` if Postgres-specific. Update [TOOLS.md](TOOLS.md).
