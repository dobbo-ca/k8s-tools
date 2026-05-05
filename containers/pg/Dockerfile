# Stage 1: Build the Go sleeper binary.
FROM golang:1.24-alpine AS builder

WORKDIR /build
COPY go.mod ./
COPY cmd/ ./cmd/

ARG TARGETOS=linux
ARG TARGETARCH

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -ldflags="-s -w" -o /sleeper ./cmd/sleeper/

# Stage 2: Wolfi runtime + core toolset + Postgres + Python.
FROM cgr.dev/chainguard/wolfi-base:latest

ARG PG_MAJOR=17

COPY containers/install-core.sh /tmp/install-core.sh
RUN /bin/sh /tmp/install-core.sh && rm /tmp/install-core.sh

# PostgreSQL tools. The unsuffixed pkg has pgbench (Wolfi puts it with the
# server, not contrib); -client provides psql/pg_dump/pg_restore.
RUN apk add --no-cache \
    postgresql-${PG_MAJOR} \
    postgresql-${PG_MAJOR}-client \
    postgresql-${PG_MAJOR}-contrib

# Python 3.13 with `python`/`pip` aliases on PATH, plus PG-version-matched
# psycopg v3. PG15 has no version-matched flavor; fall back to the unsuffixed
# package (psycopg v3 supports PG 9.6+ regardless of suffix).
RUN apk add --no-cache python-3.13 py3.13-pip && \
    ( apk add --no-cache py3.13-psycopg-${PG_MAJOR} || \
      apk add --no-cache py3.13-psycopg )

# Pre-bake helpers commonly used in PG maintenance/migration scripts.
# Wolfi's python is PEP 668 externally-managed, so use --break-system-packages
# for the bake step. Runtime users get PIP_TARGET=/tmp/site (writable).
RUN pip install --no-cache-dir --break-system-packages \
    pgcli rich click tenacity

ENV PIP_TARGET=/tmp/site \
    PYTHONPATH=/tmp/site

# wal-g via upstream binary release. Asset naming: wal-g-pg-<ubuntu-ver>-<arch>.
RUN WALG_ARCH=$(uname -m | sed 's/x86_64/amd64/') && \
    wget -q "https://github.com/wal-g/wal-g/releases/latest/download/wal-g-pg-24.04-${WALG_ARCH}" \
      -O /usr/local/bin/wal-g && \
    chmod +x /usr/local/bin/wal-g && \
    wal-g --version | head -1

# pgcenter via upstream binary release — amd64 only; arm64 gets a stub script.
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
      PGCENTER_VERSION=$(wget -qO- "https://api.github.com/repos/lesovsky/pgcenter/releases/latest" | \
        jq -r '.tag_name' | sed 's/^v//') && \
      wget -q "https://github.com/lesovsky/pgcenter/releases/download/v${PGCENTER_VERSION}/pgcenter_${PGCENTER_VERSION}_linux_amd64.tar.gz" \
        -O /tmp/pgcenter.tar.gz && \
      tar -xzf /tmp/pgcenter.tar.gz -C /usr/local/bin/ pgcenter && \
      chmod +x /usr/local/bin/pgcenter && \
      rm /tmp/pgcenter.tar.gz && \
      pgcenter --version | head -1; \
    else \
      printf '#!/bin/sh\necho "pgcenter: not available on %s — upstream ships amd64 only" >&2\nexit 1\n' "$ARCH" > /usr/local/bin/pgcenter && \
      chmod +x /usr/local/bin/pgcenter; \
    fi

# pgbadger — single Perl script; releases ship no binary asset.
RUN apk add --no-cache perl && \
    PGBADGER_VERSION=$(wget -qO- "https://api.github.com/repos/darold/pgbadger/releases/latest" | \
      jq -r '.tag_name') && \
    wget -q "https://raw.githubusercontent.com/darold/pgbadger/${PGBADGER_VERSION}/pgbadger" \
      -O /usr/local/bin/pgbadger && \
    chmod +x /usr/local/bin/pgbadger && \
    pgbadger --version | head -1

# Final hardening pass for anything new picked up SUID/SGID.
RUN find / -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

COPY --from=builder /sleeper /usr/local/bin/sleeper
COPY TOOLS.md /TOOLS.md

# Welcome banner — same plumbing as the full image; banner.sh detects psql
# and python presence at runtime and adapts the printed lines.
COPY containers/banner.sh /etc/profile.d/k8s-tools-banner.sh
RUN printf '%s\n' \
    'case $- in *i*) ;; *) return ;; esac' \
    'for f in /etc/profile.d/*.sh; do [ -r "$f" ] && . "$f"; done' \
    > /etc/bash.bashrc && \
    chmod 0644 /etc/profile.d/k8s-tools-banner.sh /etc/bash.bashrc

USER 65534:65534

ENTRYPOINT ["/usr/local/bin/sleeper"]
