#!/bin/sh
# Core diagnostic toolset shared by every k8s-tools image variant.
# Runs as root in the build stage; assumes a Wolfi base image.
set -eu

apk add --no-cache \
    bind-tools \
    drill \
    openssl \
    curl \
    wget \
    nmap \
    iputils \
    mtr \
    tcptraceroute \
    netcat-openbsd \
    iproute2 \
    net-tools \
    neovim \
    jq \
    yq \
    bash \
    coreutils \
    procps \
    less \
    strace \
    tcpdump \
    iperf3 \
    htop \
    tree \
    file \
    ca-certificates

# sslscan from source (no Wolfi pkg). Links dynamically against system OpenSSL.
apk add --no-cache build-base git openssl-dev
git clone --depth 1 https://github.com/rbsec/sslscan.git /tmp/sslscan
( cd /tmp/sslscan && make && mv sslscan /usr/local/bin/ )
rm -rf /tmp/sslscan
apk del build-base openssl-dev

# testssl.sh — bash script, not in any package repo.
git clone --depth 1 https://github.com/drwetter/testssl.sh.git /opt/testssl
ln -s /opt/testssl/testssl.sh /usr/local/bin/testssl
apk del git

# Strip SUID/SGID bits as a hardening pass.
find / -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

# Read-only rootfs compatibility: ensure /tmp is sticky-writable.
chmod 1777 /tmp
