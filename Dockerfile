# syntax=docker/dockerfile:1
# V2-for-Koyeb, modernised for PaaS Docker deployment
# Nginx + WebSocket + VMess / VLESS, with Xray-core.
# PaaS terminates TLS in front of this container, so there is
# deliberately no Reality / XTLS-Vision here. Reality belongs on a VPS.
#
# Pinned versions, verified 2026-11-16:
# - nginx 1.30.6-alpine, digest from Docker Hub
# - Xray-core v26.11.9, released 2026-11-09, not a pre-release
# - SHA-256 values below are from the official .dgst files for that release
FROM nginx:1.30.6-alpine@sha256:901e593c95dc85f5a729f5765516321366ef4ac401821431d408897e95287d0a

LABEL org.opencontainers.image.title="v2-for-koyeb (Xray-core)"
LABEL org.opencontainers.image.source="https://github.com/fscarmen/V2-for-Koyeb"
LABEL org.opencontainers.image.licenses="MIT"

ARG XRAY_VERSION=v26.11.9
ARG TARGETARCH

WORKDIR /app

COPY nginx.conf.template config.json.template entrypoint.sh ./

# Download one pinned Xray release for the build arch and verify it.
# amd64 -> Xray-linux-64.zip
# arm64 -> Xray-linux-arm64-v8a.zip
# No "latest" lookup at build time, so the same commit always builds the same image.
RUN apk add --no-cache ca-certificates \
    && apk add --no-cache --virtual .build-deps curl unzip \
    && case "${TARGETARCH}" in \
         amd64) XRAY_FILE="Xray-linux-64.zip"; \
                XRAY_SHA256="b651f7e1d9966ee2c1b1ee1bf8b52c72771824d3065dce96bbc8bcc19ed95f82" ;; \
         arm64) XRAY_FILE="Xray-linux-arm64-v8a.zip"; \
                XRAY_SHA256="64ed6858982a7f5eb85d88b811089063bd4f17561f4c8f44e0f1dc8e6f6430be" ;; \
         *) echo "unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && curl -fsSL -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${XRAY_FILE}" \
    && printf '%s  /tmp/xray.zip\n' "${XRAY_SHA256}" | sha256sum -c - \
    && mkdir -p /tmp/xray /usr/local/share/xray \
    && unzip -o /tmp/xray.zip xray geoip.dat geosite.dat -d /tmp/xray \
    && install -m 0755 /tmp/xray/xray /usr/local/bin/xray \
    && install -m 0644 /tmp/xray/geoip.dat /usr/local/share/xray/geoip.dat \
    && install -m 0644 /tmp/xray/geosite.dat /usr/local/share/xray/geosite.dat \
    && chmod 0755 entrypoint.sh \
    && apk del .build-deps \
    && rm -rf /tmp/xray /tmp/xray.zip /var/cache/apk/*

ENV XRAY_LOCATION_ASSET=/usr/local/share/xray

# Documentary only. PaaS platforms that inject $PORT override the
# default at runtime and the entrypoint makes nginx listen on it.
# Default is 80 to match the original repo and Koyeb's port 80 setting.
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD sh -c 'wget -q -O /dev/null "http://127.0.0.1:${PORT:-80}/health"'

ENTRYPOINT ["/app/entrypoint.sh"]
