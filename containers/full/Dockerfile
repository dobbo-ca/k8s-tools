# Stage 1: Build the Go sleeper binary.
FROM golang:1.24-alpine AS builder

WORKDIR /build
COPY go.mod ./
COPY cmd/ ./cmd/

ARG TARGETOS=linux
ARG TARGETARCH

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -ldflags="-s -w" -o /sleeper ./cmd/sleeper/

# Stage 2: Wolfi runtime with the shared core toolset.
FROM cgr.dev/chainguard/wolfi-base:latest

COPY containers/install-core.sh /tmp/install-core.sh
RUN /bin/sh /tmp/install-core.sh && rm /tmp/install-core.sh

COPY --from=builder /sleeper /usr/local/bin/sleeper
COPY TOOLS.md /TOOLS.md

# Welcome banner for interactive shells. /etc/profile sources /etc/profile.d/*.sh
# for login shells; /etc/bash.bashrc covers `kubectl exec -it -- bash`.
COPY containers/banner.sh /etc/profile.d/k8s-tools-banner.sh
RUN printf '%s\n' \
    'case $- in *i*) ;; *) return ;; esac' \
    'for f in /etc/profile.d/*.sh; do [ -r "$f" ] && . "$f"; done' \
    > /etc/bash.bashrc && \
    chmod 0644 /etc/profile.d/k8s-tools-banner.sh /etc/bash.bashrc

USER 65534:65534

ENTRYPOINT ["/usr/local/bin/sleeper"]
