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
    tcptraceroute \
    # Port/Socket
    netcat-openbsd \
    iproute2 \
    net-tools \
    # Supporting
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

# Install sslscan from source (not in Wolfi repos). Links dynamically against
# system OpenSSL — keeps image small and tracks the system's TLS lib for patches.
RUN apk add --no-cache build-base git openssl-dev && \
    git clone --depth 1 https://github.com/rbsec/sslscan.git /tmp/sslscan && \
    cd /tmp/sslscan && make && mv sslscan /usr/local/bin/ && \
    cd / && rm -rf /tmp/sslscan && \
    apk del build-base git openssl-dev

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

# Welcome banner for interactive shells. Wolfi's /etc/profile sources
# /etc/profile.d/*.sh for login shells; we add /etc/bash.bashrc so
# `kubectl exec -it -- bash` (non-login interactive) sees it too.
COPY containers/full/banner.sh /etc/profile.d/k8s-tools-banner.sh
RUN printf '%s\n' \
    'case $- in *i*) ;; *) return ;; esac' \
    'for f in /etc/profile.d/*.sh; do [ -r "$f" ] && . "$f"; done' \
    > /etc/bash.bashrc && \
    chmod 0644 /etc/profile.d/k8s-tools-banner.sh /etc/bash.bashrc

USER 65534:65534

ENTRYPOINT ["/usr/local/bin/sleeper"]
