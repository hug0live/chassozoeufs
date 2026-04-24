#!/bin/sh
set -eu

hosts="${PUBLIC_HOSTS:-localhost,127.0.0.1,raspberrypi.local}"
hosts="$(printf '%s' "$hosts" | tr ',' ' ')"

cat > /etc/caddy/Caddyfile <<EOF
$hosts {
  tls internal
  reverse_proxy egg-hunt-server:8181
}
EOF

exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile
