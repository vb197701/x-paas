#!/bin/sh
# PaaS entrypoint: render the nginx and Xray configs from templates,
# validate both, then start nginx and exec Xray as PID 1.
# Required: UUID. Optional: PORT (default 8080), VMESS_WSPATH, VLESS_WSPATH.
set -eu

PORT="${PORT:-8080}"
UUID="${UUID:-}"
VMESS_WSPATH="${VMESS_WSPATH:-/vmess}"
VLESS_WSPATH="${VLESS_WSPATH:-/vless}"

# --- validation: fail fast instead of starting with a broken config ---
case "${PORT}" in
  ''|*[!0-9]*)
    echo "error: PORT must be a number, got '${PORT}'" >&2; exit 1 ;;
esac
if [ "${PORT}" -lt 1 ] || [ "${PORT}" -gt 65535 ]; then
  echo "error: PORT out of range: ${PORT}" >&2; exit 1
fi
if [ "${PORT}" = "11000" ] || [ "${PORT}" = "12000" ]; then
  echo "error: PORT ${PORT} collides with the internal Xray ports 11000/12000" >&2; exit 1
fi

if [ -z "${UUID}" ]; then
  echo "error: UUID is not set. Generate one and set it as an environment variable." >&2; exit 1
fi
if [ "${UUID}" = "de04add9-5c68-8bab-950c-08cd5320df18" ]; then
  echo "error: UUID is still the public default from the old README. Generate your own." >&2; exit 1
fi
case "${UUID}" in
  ????????-????-????-????-????????????) ;;
  *) echo "error: UUID does not look like a UUID: ${UUID}" >&2; exit 1 ;;
esac

for p in "${VMESS_WSPATH}" "${VLESS_WSPATH}"; do
  case "${p}" in
    /*) ;;
    *) echo "error: WebSocket path must start with /: ${p}" >&2; exit 1 ;;
  esac
  case "${p}" in
    *[[:space:]]*|*'#'*|*'?'*) echo "error: WebSocket path contains a space, # or ?: ${p}" >&2; exit 1 ;;
  esac
done
if [ "${VMESS_WSPATH}" = "${VLESS_WSPATH}" ]; then
  echo "error: VMESS_WSPATH and VLESS_WSPATH must be different" >&2; exit 1
fi

# --- render configs ---
# Templates use __PORT__, __UUID__, __VMESS_WSPATH__, __VLESS_WSPATH__.
# sed with # as the delimiter avoids clashing with / in the paths.
sed -e "s#__PORT__#${PORT}#g" \
    -e "s#__VMESS_WSPATH__#${VMESS_WSPATH}#g" \
    -e "s#__VLESS_WSPATH__#${VLESS_WSPATH}#g" \
    /app/nginx.conf.template > /etc/nginx/nginx.conf

sed -e "s#__UUID__#${UUID}#g" \
    -e "s#__VMESS_WSPATH__#${VMESS_WSPATH}#g" \
    -e "s#__VLESS_WSPATH__#${VLESS_WSPATH}#g" \
    /app/config.json.template > /app/config.json

# --- validate before starting anything ---
nginx -t
/usr/local/bin/xray run -test -config /app/config.json

# nginx runs as a daemon here, Xray stays in the foreground as PID 1
# so the PaaS platform gets the container's exit signal correctly.
nginx
exec /usr/local/bin/xray run -config /app/config.json
