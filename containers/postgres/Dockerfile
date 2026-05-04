ARG FULL_IMAGE=ghcr.io/dobbo-ca/k8s-tools:full-latest
FROM ${FULL_IMAGE}

ARG PG_MAJOR=17

USER root

# PostgreSQL tools. The -client package provides psql/pg_dump/pg_restore;
# the unsuffixed package provides pgbench (Wolfi ships it with the server, not contrib).
RUN apk add --no-cache \
    postgresql-${PG_MAJOR} \
    postgresql-${PG_MAJOR}-client \
    postgresql-${PG_MAJOR}-contrib

RUN pgbench --version && psql --version && pg_dump --version

# wal-g via upstream binary release (not in Wolfi apk).
# Asset naming: wal-g-pg-<ubuntu-version>-<arch>; Ubuntu glibc is compatible with Wolfi's.
RUN WALG_ARCH=$(uname -m | sed 's/x86_64/amd64/') && \
    wget -q "https://github.com/wal-g/wal-g/releases/latest/download/wal-g-pg-24.04-${WALG_ARCH}" \
      -O /usr/local/bin/wal-g && \
    chmod +x /usr/local/bin/wal-g && \
    wal-g --version | head -1

# pgcenter via upstream binary release. Upstream only ships amd64; arm64 users
# get a stub that prints a friendly message until upstream publishes arm64 builds.
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

# pgbadger is a single Perl script. Releases don't ship a binary asset, so pull
# it from raw GitHub at the latest tag.
RUN apk add --no-cache perl && \
    PGBADGER_VERSION=$(wget -qO- "https://api.github.com/repos/darold/pgbadger/releases/latest" | \
      jq -r '.tag_name') && \
    wget -q "https://raw.githubusercontent.com/darold/pgbadger/${PGBADGER_VERSION}/pgbadger" \
      -O /usr/local/bin/pgbadger && \
    chmod +x /usr/local/bin/pgbadger && \
    pgbadger --version | head -1

# pgbackrest deferred — not in Wolfi APK, source build needs deps unavailable in
# Wolfi (libc-dev). Will be added once Wolfi ships pgbackrest or we find a
# working binary release path. Tracked in README.

# Security hardening: strip any new SUID/SGID bits.
RUN find / -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

USER 65534:65534
