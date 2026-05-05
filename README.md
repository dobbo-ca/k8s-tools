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
ghcr.io/dobbo-ca/k8s-tools:pg-15-latest
ghcr.io/dobbo-ca/k8s-tools:pg-16-latest
ghcr.io/dobbo-ca/k8s-tools:pg-17-latest
ghcr.io/dobbo-ca/k8s-tools:pg-18-latest
```

| Variant | Includes |
|---|---|
| `full` | Core diagnostic toolset: DNS (dig, drill), TLS (openssl, sslscan, testssl), HTTP (curl, wget, nmap), network (mtr, tcptraceroute, ping), sockets (nc, ss), tracing (tcpdump, strace), bandwidth (iperf3), JSON/YAML (jq, yq), editor (nvim). |
| `pg-{15,16,17,18}` | Core toolset **plus** PostgreSQL: psql, pg_dump, pg_restore, pgbench, WAL-G, pgCenter (amd64 only), pgBadger. Plus Python 3.13 with PG-version-matched **psycopg v3** and pre-baked migration helpers: `pgcli`, `rich`, `click`, `tenacity`. |

Both variants share the same core install via `containers/install-core.sh`,
so any tool in `full` is also in `pg-*`.

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
# One-shot debug shell
kubectl run k8s-tools --image=ghcr.io/dobbo-ca/k8s-tools:full-latest \
  --restart=Never --rm -it --command -- bash

# Long-running pod
kubectl run k8s-tools --image=ghcr.io/dobbo-ca/k8s-tools:full-latest
kubectl exec -it k8s-tools -- bash
```

For Postgres + Python migration scripting:

```bash
kubectl run pg-debug --image=ghcr.io/dobbo-ca/k8s-tools:pg-17-latest
kubectl exec -it pg-debug -- bash
# inside:
psql -h my-db.svc.cluster.local -U postgres -d app
python -c 'import psycopg; print(psycopg.connect("postgresql://..."))'
pgcli postgresql://user@host/db   # interactive psql with autocomplete
```

The interactive shell prints a categorized tool banner on entry — see
[TOOLS.md](TOOLS.md) for the full reference.

### Runtime `pip install`

The image ships `pip` with `PIP_TARGET=/tmp/site` and `PYTHONPATH=/tmp/site`,
so `pip install <pkg>` works inside an ephemeral pod without root or a real
home directory:

```bash
pip install boto3       # lands in /tmp/site, importable immediately
```

Two caveats:
- The pod must allow writes to `/tmp` (default) **and** the filesystem
  must not be read-only — set `securityContext.readOnlyRootFilesystem=false`
  in your pod spec or override the Helm value.
- For repeatable scripts, prefer baking the dependency into a custom image
  built FROM `pg-<version>-latest`.

---

## Helm chart

```bash
helm install diag charts/k8s-tools/
```

Key values (see [`charts/k8s-tools/values.yaml`](charts/k8s-tools/values.yaml)):

| Value | Default | Description |
|---|---|---|
| `variant` | `full` | `full` or `pg` |
| `postgres.version` | `"17"` | PG major version (15/16/17/18); only used when `variant=pg` |
| `image.tag` | `""` | Override; leave empty to auto-resolve from variant |
| `persistence.enabled` | `false` | If true, deploys as StatefulSet with PVC mounted at `/data` |
| `persistence.size` | `10Gi` | PVC size |

### Postgres debug with persistence (e.g., capturing big dumps)

```bash
helm install pg-debug charts/k8s-tools/ \
  --set variant=pg \
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

# Any pg variant (independent of full — both share install-core.sh)
docker buildx build -f containers/pg/Dockerfile \
  --build-arg PG_MAJOR=17 \
  -t k8s-tools:pg-17-local .
```

---

## Contributing

1. Open a PR — the CI workflow builds every variant and runs Trivy.
2. CRITICAL/HIGH CVEs are a blocker; bump the offending package or wait for
   the next Wolfi sync if the fix is upstream.
3. Tools that belong to the **core** toolset go in
   `containers/install-core.sh` (consumed by both variants).
4. PostgreSQL- or Python-specific additions go in `containers/pg/Dockerfile`.
   Update [TOOLS.md](TOOLS.md) alongside the change.
