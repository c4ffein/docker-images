#!/usr/bin/env bash
#
# Smoke test for the nginx-acme image: runs as non-root, the ACME module is
# present and loaded, the shipped config and an acme_certificate server block
# parse, HTTP is served and the container reports healthy - all under the same
# hardening flags the Makefile and the systemd unit use. No network beyond
# localhost.
#
# This is what `make nginx-test` and CI run.
#
# Usage: bash nginx/test/run-smoke.sh [image]   (default: nginx-acme:latest)
#   NGINX_TEST_PORT   host port for the HTTP check (default: 8080)
#
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE="${1:-nginx-acme:latest}"
PORT="${NGINX_TEST_PORT:-8080}"
NAME="nginx-acme-smoke"

# Keep in sync with NGINX_HARDENING in the Makefile and nginx-docker.service.
HARDENING=(
    --read-only
    --tmpfs /tmp:rw,noexec,nosuid,size=64m
    --cap-drop ALL
    --cap-add NET_BIND_SERVICE
    --security-opt no-new-privileges
    --pids-limit 256
)

TMP=$(mktemp -d)
# mktemp gives 0700; the container (uid 101) must be able to traverse into the
# bind-mounted directories.
chmod 755 "$TMP"
mkdir -p "$TMP/conf.d" "$TMP/www"

cleanup() {
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo
        echo "=== $NAME logs ==="
        docker logs "$NAME" 2>&1 || true
    fi
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    rm -rf "$TMP"
}
trap cleanup EXIT

echo "→ nginx binary"
docker run --rm "$IMAGE" nginx -v

echo "→ runs as uid 101, not root"
uid=$(docker run --rm "$IMAGE" id -u)
[ "$uid" = "101" ] || { echo "✗ container runs as uid $uid"; exit 1; }

echo "→ ACME module file present"
docker run --rm "$IMAGE" test -f /usr/lib/nginx/modules/ngx_http_acme_module.so

# `nginx -t` never starts workers, so no ACME request is made by any of the
# config checks below.
echo "→ shipped config parses (load_module, acme_issuer, acme_shared_zone)"
docker run --rm "$IMAGE" nginx -t

echo "→ acme_certificate server block parses"
sed 's/example\.com/smoke.example.test/g' examples/tls.conf.example > "$TMP/conf.d/tls.conf"
docker run --rm -v "$TMP/conf.d:/etc/nginx/conf.d:ro" "$IMAGE" nginx -t

echo "→ HTTP server on port $PORT, read-only rootfs, no capabilities"
echo "<html><body>Smoke OK</body></html>" > "$TMP/www/index.html"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" "${HARDENING[@]}" \
    -p "$PORT:80" -v "$TMP/www:/var/www/html:ro" "$IMAGE" >/dev/null
for _ in $(seq 1 15); do
    if curl -fsS "http://localhost:$PORT" 2>/dev/null | grep -q "Smoke OK"; then
        break
    fi
    sleep 2
done
curl -fsS "http://localhost:$PORT" | grep -q "Smoke OK" || { echo "✗ HTTP server did not answer"; exit 1; }

# From the host the request arrives from the bridge gateway, not loopback, so
# the deny rule must kick in. (Rootless Docker rewrites the source to loopback
# and would see a 200 here; this test assumes a rootful daemon, as CI has.)
echo "→ /healthz is loopback-only"
code=$(curl -s -o /dev/null -w '%{http_code}' "http://localhost:$PORT/healthz")
[ "$code" = "403" ] || { echo "✗ /healthz answered $code from outside the container, expected 403"; exit 1; }

echo "→ container health check"
status=""
for _ in $(seq 1 20); do
    status=$(docker inspect -f '{{.State.Health.Status}}' "$NAME")
    [ "$status" = "healthy" ] && break
    [ "$status" = "unhealthy" ] && { echo "✗ container reports unhealthy"; exit 1; }
    sleep 3
done
[ "$status" = "healthy" ] || { echo "✗ container not healthy after 60s (status: $status)"; exit 1; }

echo
echo "✓ smoke passed: non-root, module loaded, config parses, HTTP served, healthy"
