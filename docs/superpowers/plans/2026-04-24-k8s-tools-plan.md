# k8s-tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and publish multi-arch diagnostic container images for Kubernetes, with a Helm chart for deployment and CI/CD via GitHub Actions.

**Architecture:** Two container variants (full, postgres) built on Chainguard Wolfi, running a no-op Go binary as PID 1. Images published to ghcr.io via weekly scheduled and merge-to-main workflows. Helm chart deploys as Deployment or StatefulSet based on persistence needs.

**Tech Stack:** Go, Docker (multi-stage builds), Helm 3, GitHub Actions, Trivy, Chainguard Wolfi, ghcr.io

---

## File Map

| File | Responsibility |
|------|----------------|
| `cmd/sleeper/main.go` | Go binary — blocks forever via `select{}` |
| `go.mod` | Go module definition |
| `containers/full/Dockerfile` | Full diagnostic image (Wolfi + all tools) |
| `containers/postgres/Dockerfile` | Postgres image (FROM full + PG client/backup/diagnostic tools) |
| `charts/k8s-tools/Chart.yaml` | Helm chart metadata |
| `charts/k8s-tools/values.yaml` | Default values (variant, image, persistence) |
| `charts/k8s-tools/templates/_helpers.tpl` | Template helpers (image tag resolution, labels) |
| `charts/k8s-tools/templates/deployment.yaml` | Deployment (when persistence disabled) |
| `charts/k8s-tools/templates/statefulset.yaml` | StatefulSet (when persistence enabled) |
| `charts/k8s-tools/templates/serviceaccount.yaml` | ServiceAccount |
| `.github/workflows/ci.yaml` | PR gate — build + Trivy scan |
| `.github/workflows/release.yaml` | Main merge — build, tag, push to ghcr.io |
| `.github/workflows/scheduled-build.yaml` | Weekly cron — same as release |
| `TOOLS.md` | In-container cheatsheet with example commands |
| `README.md` | Repo overview, usage, quickstart |
| `.gitignore` | Standard Go + editor ignores |

---

## Task 1: Initialize Go Module and Sleeper Binary

**Files:**
- Create: `go.mod`
- Create: `cmd/sleeper/main.go`
- Create: `.gitignore`

- [ ] **Step 1: Create go.mod**

```
go mod init github.com/dobbo-ca/k8s-tools
```

Run: `cd /Users/christopherdobbyn/work/dobbo-ca/k8s-tools && go mod init github.com/dobbo-ca/k8s-tools`

- [ ] **Step 2: Create the sleeper binary**

Write `cmd/sleeper/main.go`:

```go
package main

import (
	"fmt"
	"os"
	"os/signal"
	"syscall"
)

func main() {
	fmt.Println("k8s-tools: container ready")

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGTERM, syscall.SIGINT)

	<-sig
	fmt.Println("k8s-tools: shutting down")
}
```

Note: We use signal handling instead of bare `select{}` so the container responds cleanly to SIGTERM from Kubernetes (graceful shutdown). Zero CPU — blocks on channel receive.

- [ ] **Step 3: Verify it compiles**

Run: `CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /dev/null ./cmd/sleeper/`
Expected: Exit 0, no output.

- [ ] **Step 4: Create .gitignore**

Write `.gitignore`:

```
# Binaries
sleeper
*.exe
*.out

# IDE
.idea/
.vscode/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db
```

- [ ] **Step 5: Commit**

```bash
git add go.mod cmd/sleeper/main.go .gitignore
git commit -m "feat: add Go sleeper binary and module init

Static binary that blocks on signal, responds to SIGTERM for
graceful Kubernetes shutdown. Zero CPU usage."
```

---

## Task 2: Full Variant Dockerfile

**Files:**
- Create: `containers/full/Dockerfile`

- [ ] **Step 1: Create the full Dockerfile**

Write `containers/full/Dockerfile`:

```dockerfile
# Stage 1: Build the Go binary
FROM golang:1.24-alpine AS builder

WORKDIR /build
COPY go.mod ./
COPY cmd/ ./cmd/

ARG TARGETOS=linux
ARG TARGETARCH

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -ldflags="-s -w" -o /sleeper ./cmd/sleeper/

# Stage 2: Install tools on Wolfi
FROM cgr.dev/chainguard/wolfi-base:latest

# DNS tools
RUN apk add --no-cache \
    bind-tools \
    drill \
    # SSL/TLS
    openssl \
    # HTTP
    curl \
    wget \
    nmap \
    # Network/Routing
    iputils \
    mtr \
    traceroute \
    # Port/Socket
    netcat-openbsd \
    iproute2 \
    net-tools \
    # Supporting
    neovim \
    jq \
    yq \
    bash \
    less \
    strace \
    tcpdump \
    iperf3 \
    htop \
    tree \
    file \
    ca-certificates

# Install sslscan from source (not in Wolfi repos)
RUN apk add --no-cache build-base git && \
    git clone --depth 1 https://github.com/rbsec/sslscan.git /tmp/sslscan && \
    cd /tmp/sslscan && make static && mv sslscan /usr/local/bin/ && \
    cd / && rm -rf /tmp/sslscan && \
    apk del build-base git

# Install testssl.sh
RUN apk add --no-cache git && \
    git clone --depth 1 https://github.com/drwetter/testssl.sh.git /opt/testssl && \
    ln -s /opt/testssl/testssl.sh /usr/local/bin/testssl && \
    apk del git

# Security hardening: strip SUID/SGID bits
RUN find / -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

# Create writable tmp for read-only rootfs compatibility
RUN chmod 1777 /tmp

# Copy the Go binary
COPY --from=builder /sleeper /usr/local/bin/sleeper

# Copy TOOLS.md into the container
COPY TOOLS.md /TOOLS.md

USER 65534:65534

ENTRYPOINT ["/usr/local/bin/sleeper"]
```

Note: `sslscan` and `testssl.sh` are not in Wolfi's package repos, so we build/clone them. If Wolfi adds them later, switch to `apk`. The `apk del` lines remove build deps to keep image size down.

- [ ] **Step 2: Verify Dockerfile syntax**

Run: `docker buildx build --check -f containers/full/Dockerfile .`
Expected: No syntax errors. (This only checks syntax, does not build.)

If `--check` is not supported by the local Docker version, skip this step — the actual build in a later task will catch errors.

- [ ] **Step 3: Commit**

```bash
git add containers/full/Dockerfile
git commit -m "feat: add full variant Dockerfile

Wolfi-based multi-stage build. Installs DNS, SSL/TLS, HTTP, network,
and supporting diagnostic tools. Runs as nobody (65534), strips
SUID/SGID bits."
```

---

## Task 3: Postgres Variant Dockerfile

**Files:**
- Create: `containers/postgres/Dockerfile`

- [ ] **Step 1: Create the postgres Dockerfile**

Write `containers/postgres/Dockerfile`:

```dockerfile
ARG FULL_IMAGE=ghcr.io/dobbo-ca/k8s-tools:full-latest
FROM ${FULL_IMAGE}

ARG PG_MAJOR=17

USER root

# PostgreSQL client tools from official APK repos
# Wolfi tracks PG versions; package names include the major version
RUN apk add --no-cache \
    postgresql-${PG_MAJOR}-client \
    postgresql-${PG_MAJOR}-contrib

# pgbench is typically included in contrib, verify it exists
RUN pgbench --version

# Install pgBackRest
RUN apk add --no-cache \
    pgbackrest || \
    (echo "WARN: pgbackrest not in apk, installing from source" && \
     apk add --no-cache build-base libc-dev openssl-dev libxml2-dev lz4-dev zstd-dev bzip2-dev && \
     git clone --depth 1 https://github.com/pgbackrest/pgbackrest.git /tmp/pgbackrest && \
     cd /tmp/pgbackrest/src && ./configure && make -j$(nproc) && mv pgbackrest /usr/local/bin/ && \
     cd / && rm -rf /tmp/pgbackrest && \
     apk del build-base libc-dev openssl-dev libxml2-dev lz4-dev zstd-dev bzip2-dev)

# Install WAL-G
RUN apk add --no-cache \
    wal-g || \
    (echo "WARN: wal-g not in apk, installing binary release" && \
     WALG_ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
     wget -q "https://github.com/wal-g/wal-g/releases/latest/download/wal-g-pg-linux-${WALG_ARCH}" \
       -O /usr/local/bin/wal-g && \
     chmod +x /usr/local/bin/wal-g)

# Install pgCenter
RUN PGCENTER_ARCH=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/') && \
    PGCENTER_VERSION=$(wget -qO- "https://api.github.com/repos/lesovsky/pgcenter/releases/latest" | \
      jq -r '.tag_name' | sed 's/^v//') && \
    wget -q "https://github.com/lesovsky/pgcenter/releases/download/v${PGCENTER_VERSION}/pgcenter_${PGCENTER_VERSION}_linux_${PGCENTER_ARCH}.tar.gz" \
      -O /tmp/pgcenter.tar.gz && \
    tar -xzf /tmp/pgcenter.tar.gz -C /usr/local/bin/ pgcenter && \
    chmod +x /usr/local/bin/pgcenter && \
    rm /tmp/pgcenter.tar.gz

# Install pgBadger
RUN apk add --no-cache perl && \
    (apk add --no-cache pgbadger || \
     (wget -q "https://github.com/darold/pgbadger/releases/latest/download/pgbadger" \
        -O /usr/local/bin/pgbadger && \
      chmod +x /usr/local/bin/pgbadger)) 

# Security hardening: strip any new SUID/SGID bits
RUN find / -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

USER 65534:65534
```

Note: The Dockerfile tries `apk` first for each tool and falls back to binary releases/source builds. This makes it resilient to Wolfi package availability. The `FULL_IMAGE` ARG lets CI pass the just-built full image, or defaults to ghcr.io for local builds.

- [ ] **Step 2: Commit**

```bash
git add containers/postgres/Dockerfile
git commit -m "feat: add postgres variant Dockerfile

FROM full image, adds PG client tools (psql, pg_dump, pg_restore,
pgbench), pgBackRest, WAL-G, pgCenter, pgBadger. PG_MAJOR build-arg
for version matrix (15, 16, 17)."
```

---

## Task 4: Helm Chart

**Files:**
- Create: `charts/k8s-tools/Chart.yaml`
- Create: `charts/k8s-tools/values.yaml`
- Create: `charts/k8s-tools/templates/_helpers.tpl`
- Create: `charts/k8s-tools/templates/deployment.yaml`
- Create: `charts/k8s-tools/templates/statefulset.yaml`
- Create: `charts/k8s-tools/templates/serviceaccount.yaml`

- [ ] **Step 1: Create Chart.yaml**

Write `charts/k8s-tools/Chart.yaml`:

```yaml
apiVersion: v2
name: k8s-tools
description: Deploy diagnostic tool containers into Kubernetes
type: application
version: 0.1.0
appVersion: "latest"
```

- [ ] **Step 2: Create values.yaml**

Write `charts/k8s-tools/values.yaml`:

```yaml
# Container variant: full | postgres
variant: full

image:
  repository: ghcr.io/dobbo-ca/k8s-tools
  pullPolicy: IfNotPresent
  # Tag override — if empty, auto-resolved from variant + postgres.version
  tag: ""

postgres:
  # Only used when variant=postgres
  version: "17"

persistence:
  # When true, deploys as StatefulSet with PVC instead of Deployment
  enabled: false
  size: 10Gi
  storageClass: ""
  accessModes:
    - ReadWriteOnce

serviceAccount:
  create: true
  name: ""
  annotations: {}

resources: {}

nodeSelector: {}

tolerations: []

affinity: {}

podAnnotations: {}

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 65534
  runAsGroup: 65534
  fsGroup: 65534
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop:
      - ALL
```

- [ ] **Step 3: Create _helpers.tpl**

Write `charts/k8s-tools/templates/_helpers.tpl`:

```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "k8s-tools.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "k8s-tools.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "k8s-tools.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "k8s-tools.selectorLabels" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "k8s-tools.selectorLabels" -}}
app.kubernetes.io/name: {{ include "k8s-tools.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Service account name
*/}}
{{- define "k8s-tools.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "k8s-tools.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolve image tag from variant + postgres version
*/}}
{{- define "k8s-tools.imageTag" -}}
{{- if .Values.image.tag }}
{{- .Values.image.tag }}
{{- else if eq .Values.variant "postgres" }}
{{- printf "postgres-pg%s-latest" .Values.postgres.version }}
{{- else }}
{{- printf "full-latest" }}
{{- end }}
{{- end }}
```

- [ ] **Step 4: Create deployment.yaml**

Write `charts/k8s-tools/templates/deployment.yaml`:

```yaml
{{- if not .Values.persistence.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "k8s-tools.fullname" . }}
  labels:
    {{- include "k8s-tools.labels" . | nindent 4 }}
spec:
  replicas: 1
  selector:
    matchLabels:
      {{- include "k8s-tools.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      labels:
        {{- include "k8s-tools.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "k8s-tools.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ include "k8s-tools.imageTag" . }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
{{- end }}
```

- [ ] **Step 5: Create statefulset.yaml**

Write `charts/k8s-tools/templates/statefulset.yaml`:

```yaml
{{- if .Values.persistence.enabled }}
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "k8s-tools.fullname" . }}
  labels:
    {{- include "k8s-tools.labels" . | nindent 4 }}
spec:
  serviceName: {{ include "k8s-tools.fullname" . }}
  replicas: 1
  selector:
    matchLabels:
      {{- include "k8s-tools.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      labels:
        {{- include "k8s-tools.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "k8s-tools.serviceAccountName" . }}
      securityContext:
        {{- toYaml .Values.podSecurityContext | nindent 8 }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ include "k8s-tools.imageTag" . }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          securityContext:
            {{- toYaml .Values.securityContext | nindent 12 }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            - name: data
              mountPath: /data
      volumes:
        - name: tmp
          emptyDir: {}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes:
          {{- toYaml .Values.persistence.accessModes | nindent 10 }}
        {{- if .Values.persistence.storageClass }}
        storageClassName: {{ .Values.persistence.storageClass | quote }}
        {{- end }}
        resources:
          requests:
            storage: {{ .Values.persistence.size }}
{{- end }}
```

- [ ] **Step 6: Create serviceaccount.yaml**

Write `charts/k8s-tools/templates/serviceaccount.yaml`:

```yaml
{{- if .Values.serviceAccount.create }}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "k8s-tools.serviceAccountName" . }}
  labels:
    {{- include "k8s-tools.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
```

- [ ] **Step 7: Validate chart renders**

Run: `helm template test-release charts/k8s-tools/`
Expected: Valid YAML with Deployment, ServiceAccount.

Run: `helm template test-release charts/k8s-tools/ --set persistence.enabled=true`
Expected: Valid YAML with StatefulSet + volumeClaimTemplates, no Deployment.

Run: `helm template test-release charts/k8s-tools/ --set variant=postgres`
Expected: Image tag resolves to `postgres-pg17-latest`.

- [ ] **Step 8: Commit**

```bash
git add charts/
git commit -m "feat: add Helm chart for k8s-tools

Single chart with variant toggle (full/postgres), auto-resolves image
tags. Deploys as Deployment by default, StatefulSet when persistence
is enabled. Hardened pod security context."
```

---

## Task 5: GitHub Actions — CI (PR Gate)

**Files:**
- Create: `.github/workflows/ci.yaml`

- [ ] **Step 1: Create ci.yaml**

Write `.github/workflows/ci.yaml`:

```yaml
name: CI

on:
  pull_request:
    branches: [main]

permissions:
  contents: read
  security-events: write

jobs:
  build-and-scan:
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - variant: full
            context: .
            dockerfile: containers/full/Dockerfile
            build-args: ""
          - variant: postgres-pg15
            context: .
            dockerfile: containers/postgres/Dockerfile
            build-args: |
              PG_MAJOR=15
              FULL_IMAGE=ghcr.io/${{ github.repository }}:full-ci-${{ github.sha }}
          - variant: postgres-pg16
            context: .
            dockerfile: containers/postgres/Dockerfile
            build-args: |
              PG_MAJOR=16
              FULL_IMAGE=ghcr.io/${{ github.repository }}:full-ci-${{ github.sha }}
          - variant: postgres-pg17
            context: .
            dockerfile: containers/postgres/Dockerfile
            build-args: |
              PG_MAJOR=17
              FULL_IMAGE=ghcr.io/${{ github.repository }}:full-ci-${{ github.sha }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Build full image first (for postgres variants)
        if: startsWith(matrix.variant, 'postgres')
        uses: docker/build-push-action@v6
        with:
          context: .
          file: containers/full/Dockerfile
          load: true
          tags: ghcr.io/${{ github.repository }}:full-ci-${{ github.sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Build image
        uses: docker/build-push-action@v6
        with:
          context: ${{ matrix.context }}
          file: ${{ matrix.dockerfile }}
          load: true
          tags: ghcr.io/${{ github.repository }}:${{ matrix.variant }}-ci
          build-args: ${{ matrix.build-args }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ghcr.io/${{ github.repository }}:${{ matrix.variant }}-ci
          format: sarif
          output: trivy-results.sarif
          severity: CRITICAL,HIGH
          exit-code: "1"

      - name: Upload Trivy scan results
        uses: github/codeql-action/upload-sarif@v3
        if: always()
        with:
          sarif_file: trivy-results.sarif
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/ci.yaml
git commit -m "ci: add PR gate with Trivy vulnerability scanning

Builds all variants (full + postgres-pg15/16/17) on PRs. Fails on
CRITICAL or HIGH CVEs. Uploads SARIF results to GitHub Security tab."
```

---

## Task 6: GitHub Actions — Release (Main Merge)

**Files:**
- Create: `.github/workflows/release.yaml`

- [ ] **Step 1: Create release.yaml**

Write `.github/workflows/release.yaml`:

```yaml
name: Release

on:
  push:
    branches: [main]

permissions:
  contents: read
  packages: write

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-full:
    runs-on: ubuntu-latest
    outputs:
      datestamp: ${{ steps.meta.outputs.datestamp }}
      short-sha: ${{ steps.meta.outputs.short-sha }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Generate metadata
        id: meta
        run: |
          echo "datestamp=$(date -u +%Y.%m.%d)" >> "$GITHUB_OUTPUT"
          echo "short-sha=$(git rev-parse --short=7 HEAD)" >> "$GITHUB_OUTPUT"

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to ghcr.io
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push full image
        uses: docker/build-push-action@v6
        with:
          context: .
          file: containers/full/Dockerfile
          platforms: linux/amd64,linux/arm64
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:full-latest
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:full-${{ steps.meta.outputs.datestamp }}
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:full-${{ steps.meta.outputs.datestamp }}-${{ steps.meta.outputs.short-sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  build-postgres:
    runs-on: ubuntu-latest
    needs: build-full
    strategy:
      fail-fast: false
      matrix:
        pg_major: ["15", "16", "17"]
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to ghcr.io
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push postgres image
        uses: docker/build-push-action@v6
        with:
          context: .
          file: containers/postgres/Dockerfile
          platforms: linux/amd64,linux/arm64
          push: true
          build-args: |
            PG_MAJOR=${{ matrix.pg_major }}
            FULL_IMAGE=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:full-${{ needs.build-full.outputs.datestamp }}-${{ needs.build-full.outputs.short-sha }}
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:postgres-pg${{ matrix.pg_major }}-latest
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:postgres-pg${{ matrix.pg_major }}-${{ needs.build-full.outputs.datestamp }}
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:postgres-pg${{ matrix.pg_major }}-${{ needs.build-full.outputs.datestamp }}-${{ needs.build-full.outputs.short-sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/release.yaml
git commit -m "ci: add release workflow for main merges

Builds full + postgres-pg{15,16,17} multi-arch images (amd64+arm64).
Pushes to ghcr.io with CalVer tags: datestamp, datestamp+sha, latest."
```

---

## Task 7: GitHub Actions — Scheduled Weekly Build

**Files:**
- Create: `.github/workflows/scheduled-build.yaml`

- [ ] **Step 1: Create scheduled-build.yaml**

Write `.github/workflows/scheduled-build.yaml`:

```yaml
name: Scheduled Build

on:
  schedule:
    # Every Sunday at 00:00 UTC
    - cron: "0 0 * * 0"
  workflow_dispatch: {}

permissions:
  contents: read
  packages: write

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build-full:
    runs-on: ubuntu-latest
    outputs:
      datestamp: ${{ steps.meta.outputs.datestamp }}
      short-sha: ${{ steps.meta.outputs.short-sha }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Generate metadata
        id: meta
        run: |
          echo "datestamp=$(date -u +%Y.%m.%d)" >> "$GITHUB_OUTPUT"
          echo "short-sha=$(git rev-parse --short=7 HEAD)" >> "$GITHUB_OUTPUT"

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to ghcr.io
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push full image
        uses: docker/build-push-action@v6
        with:
          context: .
          file: containers/full/Dockerfile
          platforms: linux/amd64,linux/arm64
          push: true
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:full-latest
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:full-${{ steps.meta.outputs.datestamp }}
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:full-${{ steps.meta.outputs.datestamp }}-${{ steps.meta.outputs.short-sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  build-postgres:
    runs-on: ubuntu-latest
    needs: build-full
    strategy:
      fail-fast: false
      matrix:
        pg_major: ["15", "16", "17"]
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Log in to ghcr.io
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push postgres image
        uses: docker/build-push-action@v6
        with:
          context: .
          file: containers/postgres/Dockerfile
          platforms: linux/amd64,linux/arm64
          push: true
          build-args: |
            PG_MAJOR=${{ matrix.pg_major }}
            FULL_IMAGE=${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:full-${{ needs.build-full.outputs.datestamp }}-${{ needs.build-full.outputs.short-sha }}
          tags: |
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:postgres-pg${{ matrix.pg_major }}-latest
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:postgres-pg${{ matrix.pg_major }}-${{ needs.build-full.outputs.datestamp }}
            ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:postgres-pg${{ matrix.pg_major }}-${{ needs.build-full.outputs.datestamp }}-${{ needs.build-full.outputs.short-sha }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/scheduled-build.yaml
git commit -m "ci: add weekly scheduled build

Runs every Sunday at 00:00 UTC. Same build matrix and tagging as
release workflow. Also supports manual trigger via workflow_dispatch."
```

---

## Task 8: TOOLS.md Cheatsheet

**Files:**
- Create: `TOOLS.md`

- [ ] **Step 1: Create TOOLS.md**

Write `TOOLS.md` with all installed tools grouped by category, each with example diagnostic commands. Content should cover:

**DNS:**
- `dig example.com A` / `dig @8.8.8.8 example.com`
- `host example.com`
- `nslookup example.com`
- `drill example.com`
- Debugging: check DNS resolution from within cluster, verify CoreDNS, trace delegation

**SSL/TLS:**
- `openssl s_client -connect host:443 -servername host`
- `openssl x509 -in cert.pem -text -noout` (inspect cert)
- `sslscan host:443`
- `testssl host:443`
- Debugging: cert expiry, chain issues, TLS version mismatches

**HTTP:**
- `curl -vvv https://host/path` / `curl -k` (skip TLS verify)
- `wget --spider https://host/path`
- `nmap -sV -p 443 host` (service detection)
- Debugging: response headers, redirect chains, connection timing

**Network/Routing:**
- `ping -c 4 host`
- `mtr --report host`
- `traceroute host` / `tracepath host`
- Debugging: packet loss, latency, routing issues

**Port/Socket:**
- `nc -zv host port` (TCP connectivity check)
- `ss -tlnp` (listening sockets)
- `netstat -tlnp`
- Debugging: port reachability, connection states

**Supporting:**
- `jq '.field'` / `yq '.field'`
- `tcpdump -i any -n port 5432`
- `iperf3 -c host` (bandwidth test)

**Postgres (postgres variant only):**
- `psql -h host -U user -d db`
- `pg_dump -h host -U user -d db > backup.sql`
- `pg_restore -h host -U user -d db backup.dump`
- `pgcenter top -h host -U user -d db` (live stats)
- `pgbadger /path/to/postgresql.log -o report.html`
- `pgbench -i -h host -U user -d db` (init benchmark)
- `pgbackrest --stanza=main backup`
- Query examples: top slow queries from pg_stat_statements, index usage, lock detection, connection counts

Full content should be comprehensive — approximately 200-300 lines of markdown. Each tool gets a one-line description and 2-3 example commands.

- [ ] **Step 2: Commit**

```bash
git add TOOLS.md
git commit -m "docs: add TOOLS.md diagnostic cheatsheet

Comprehensive command reference for all installed tools, grouped by
category. Includes example commands and common diagnostic scenarios."
```

---

## Task 9: README.md

**Files:**
- Create: `README.md`

- [ ] **Step 1: Create README.md**

Write `README.md` covering:

- Project purpose (1 paragraph)
- Available images with ghcr.io pull commands
- Image variants table (full, postgres-pg15/16/17)
- Tag format (CalVer: datestamp, datestamp+sha, latest)
- Quick start: `kubectl run` one-liner, `kubectl exec` into it
- Helm chart usage: install command, key values, persistence example
- Security: non-root, read-only rootfs, SUID stripped, Trivy scanned
- Building locally: `docker build` commands
- Contributing: PR process, Trivy gate

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README with usage and quickstart guide"
```

---

## Task 10: Create GitHub Repository and Push

**Files:** None (git operations only)

- [ ] **Step 1: Create the GitHub repo**

Run: `gh repo create dobbo-ca/k8s-tools --public --description "Diagnostic container images for Kubernetes" --source . --push`

This creates the repo, sets it as origin, and pushes the current branch.

- [ ] **Step 2: Verify**

Run: `gh repo view dobbo-ca/k8s-tools`
Expected: Public repo with description visible.

Run: `gh browse`
Expected: Opens repo in browser to verify contents.

---

## Task 11: Validate Full Image Build Locally

**Files:** None (docker operations only)

- [ ] **Step 1: Build the full image locally**

Run:

```bash
docker buildx build \
  -f containers/full/Dockerfile \
  -t k8s-tools:full-local \
  --load \
  .
```

Expected: Successful build. If Wolfi packages are missing or fail, document which ones and evaluate Alpine fallback.

- [ ] **Step 2: Verify the container runs and tools are present**

Run:

```bash
docker run --rm -d --name k8s-tools-test k8s-tools:full-local
docker exec k8s-tools-test dig -v
docker exec k8s-tools-test curl --version
docker exec k8s-tools-test openssl version
docker exec k8s-tools-test nvim --version
docker exec k8s-tools-test jq --version
docker exec k8s-tools-test whoami
docker stop k8s-tools-test
```

Expected: All tools respond with version info. `whoami` returns `nobody`.

- [ ] **Step 3: Fix any issues and commit**

If Wolfi is missing packages, either find the correct package name or switch individual tools to manual install. If fundamentally broken, pivot to Alpine per fallback plan.

```bash
git add -A
git commit -m "fix: adjust Dockerfile for package availability"
git push
```
