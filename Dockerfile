FROM alpine:3.21

ARG SUPERCRONIC_VERSION=v0.2.33
ARG SUPERCRONIC_SHA256=71b0d58cc53f6bd72f4571f24198b34b666629fb2e542f8b2f3e513e7cfa60b7
ARG RCLONE_VERSION=v1.68.2

RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    bash \
    curl \
    tar \
    gzip \
    findutils

# Install supercronic (container-native cron)
RUN ARCH="$(uname -m)" && \
    case "$ARCH" in \
        x86_64)  SC_ARCH="linux-amd64" ;; \
        aarch64) SC_ARCH="linux-arm64" ;; \
        armv7l)  SC_ARCH="linux-arm" ;; \
        *)       echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/aptible/supercronic/releases/download/${SUPERCRONIC_VERSION}/supercronic-${SC_ARCH}" \
        -o /usr/local/bin/supercronic && \
    chmod +x /usr/local/bin/supercronic

# Install rclone (install unzip, use it, then remove it in same layer)
RUN apk add --no-cache unzip && \
    ARCH="$(uname -m)" && \
    case "$ARCH" in \
        x86_64)  RC_ARCH="amd64" ;; \
        aarch64) RC_ARCH="arm64" ;; \
        armv7l)  RC_ARCH="arm-v7" ;; \
        *)       echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://downloads.rclone.org/${RCLONE_VERSION}/rclone-${RCLONE_VERSION}-linux-${RC_ARCH}.zip" \
        -o /tmp/rclone.zip && \
    cd /tmp && unzip rclone.zip && \
    cp /tmp/rclone-*/rclone /usr/local/bin/rclone && \
    chmod +x /usr/local/bin/rclone && \
    rm -rf /tmp/rclone* && \
    apk del unzip

RUN mkdir -p /scripts /tmp/backup

COPY entrypoint.sh /scripts/entrypoint.sh
COPY backup.sh /scripts/backup.sh

RUN chmod +x /scripts/entrypoint.sh /scripts/backup.sh

ENTRYPOINT ["/scripts/entrypoint.sh"]
