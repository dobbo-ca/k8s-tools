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
