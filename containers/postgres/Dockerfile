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
