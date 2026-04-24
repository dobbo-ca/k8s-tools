# k8s-tools Design Spec

**Date:** 2026-04-24
**Repo:** `dobbo-ca/k8s-tools` (public, GitHub)
**Registry:** `ghcr.io/dobbo-ca/k8s-tools`

## Purpose

Provide pre-built diagnostic container images for Kubernetes clusters, published to ghcr.io. Each image runs a no-op Go binary as PID 1, giving operators a long-lived container they can `kubectl exec` into for network, DNS, TLS, and database troubleshooting without scrambling to install tools during an incident.

## Container Variants

### Full (`ghcr.io/dobbo-ca/k8s-tools:full`)

- **Base image:** `cgr.dev/chainguard/wolfi-base`
- **Entrypoint:** Static Go binary (`CGO_ENABLED=0`) that blocks forever via `select{}`
- **User:** `nobody` (UID 65534, GID 65534)
- **Fallback:** If Wolfi/Chainguard causes blocking issues, pivot to Alpine. Dockerfiles are structured to make this swap straightforward.

**Installed tools:**

| Category | Tools |
|----------|-------|
| DNS | `dig`, `host`, `nslookup`, `drill` |
| SSL/TLS | `openssl`, `sslscan`, `testssl.sh` |
| HTTP | `curl`, `wget`, `nmap` |
| Network/Routing | `ping`, `mtr`, `traceroute`, `tracepath` |
| Port/Socket | `netcat` (nc), `ss`, `netstat` |
| Supporting | `neovim`, `jq`, `yq`, `bash`, `less`, `strace`, `tcpdump`, `iperf3`, `htop`, `tree`, `file`, `ca-certificates` |

### Postgres (`ghcr.io/dobbo-ca/k8s-tools:postgres-pg{15,16,17}`)

- **Base:** FROM the full image
- **Build-arg:** `PG_MAJOR` — matrix built across `15`, `16`, `17`
- **Rationale:** PostgreSQL client tools must match the server major version. AWS RDS supports PG 13-17; we target 15-17 (active support).

**Installed tools:**

| Category | Tools |
|----------|-------|
| Client | `psql`, `pg_dump`, `pg_restore`, `pg_basebackup`, `pg_isready`, `pgbench` |
| Backup | pgBackRest, WAL-G |
| Diagnostics | pgCenter (live `pg_stat_statements`/`pg_stat_activity` viewer), pgBadger (log analyzer) |

## Go Binary

```go
package main

func main() {
    select {} // blocks forever, zero CPU
}
```

- Built with `CGO_ENABLED=0 GOOS=linux`
- Multi-arch: `GOARCH=amd64` and `GOARCH=arm64`
- Static binary, no libc dependency

## Security Posture

- All containers run as UID/GID 65534 (nobody)
- Strip SETUID/SETGID bits from all binaries during build
- No shell as PID 1 — Go binary is the entrypoint
- Read-only root filesystem compatible (writable `/tmp` only)
- Trivy scan as PR merge gate — fail on CRITICAL or HIGH severity
- Chainguard/Wolfi base provides: signed images, SBOM metadata, rapid CVE patching
- Targets SOC2 and FIPS-140 compliance posture

## Image Tags

CalVer scheme. Each build produces per variant:

- `YYYY.MM.DD` — datestamp (e.g., `2026.04.24`)
- `YYYY.MM.DD-<short-sha>` — datestamp + 7-char commit hash
- `latest` — rolling pointer to most recent build

Postgres variants include the PG version in the tag: `postgres-pg16-2026.04.24`, `postgres-pg16-latest`, etc.

## Helm Chart

Single chart at `charts/k8s-tools/`.

### Key Values

```yaml
variant: full  # full | postgres
image:
  repository: ghcr.io/dobbo-ca/k8s-tools
  tag: ""  # defaults to chart appVersion
postgres:
  version: "17"  # 15 | 16 | 17, only used when variant=postgres
persistence:
  enabled: false  # when true, renders StatefulSet + PVC instead of Deployment
  size: 10Gi
  storageClass: ""
```

### Resource Logic

- `persistence.enabled: false` -> Deployment (1 replica)
- `persistence.enabled: true` -> StatefulSet (1 replica) + PVC via volumeClaimTemplate

Image tag is auto-resolved from variant + postgres.version:
- `variant: full` -> tag `full-latest` (or override)
- `variant: postgres` + `postgres.version: 16` -> tag `postgres-pg16-latest` (or override)

## GitHub Actions Workflows

### 1. PR Gate (`ci.yaml`)

- **Trigger:** Pull request to `main`
- **Steps:** Build all variants (full + postgres matrix), Trivy scan each
- **Gate:** Fail if CRITICAL or HIGH CVEs detected

### 2. Weekly Build (`scheduled-build.yaml`)

- **Trigger:** Cron — weekly (e.g., Sunday midnight UTC)
- **Steps:** Build all variants, multi-arch (amd64 + arm64) via `docker buildx` + QEMU, push to ghcr.io with CalVer tags
- **Matrix:** full + postgres-pg{15,16,17}

### 3. Release on Main Merge (`release.yaml`)

- **Trigger:** Push to `main`
- **Steps:** Same as weekly — build, tag, push to ghcr.io
- **Tags:** CalVer datestamp, datestamp+commit, latest

All workflows use `docker/build-push-action` with `platforms: linux/amd64,linux/arm64`.

## Repository Structure

```
k8s-tools/
├── cmd/
│   └── sleeper/
│       └── main.go
├── go.mod
├── containers/
│   ├── full/
│   │   └── Dockerfile
│   └── postgres/
│       └── Dockerfile
├── charts/
│   └── k8s-tools/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── deployment.yaml
│           ├── statefulset.yaml
│           ├── pvc.yaml
│           ├── serviceaccount.yaml
│           └── _helpers.tpl
├── .github/
│   └── workflows/
│       ├── ci.yaml
│       ├── scheduled-build.yaml
│       └── release.yaml
├── TOOLS.md
└── README.md
```

## TOOLS.md

Markdown cheatsheet dropped into the container's working directory (`/`). Lists every installed tool with example diagnostic commands grouped by category. Covers common incident scenarios: DNS resolution failures, TLS cert inspection, TCP connectivity checks, postgres slow query analysis, backup/restore workflows.

## Fallback Plan

If Chainguard/Wolfi causes blocking issues (package availability, build failures, compatibility):

1. Swap `cgr.dev/chainguard/wolfi-base` for `alpine:latest` in Dockerfiles
2. Replace `apk` package names as needed (mostly 1:1)
3. Accept the musl vs glibc tradeoff
4. Document the swap in the PR
