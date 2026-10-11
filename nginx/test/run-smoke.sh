#!/usr/bin/env bash
#
# Smoke test for the nginx-acme image: the ACME module is present and loaded,
# the shipped config and an acme_certificate server block parse, HTTP is
# served, and the container reports healthy. No network beyond localhost.
#
# This is what `make nginx-test` and CI run.
#
# Usage: nginx/test/run-smoke.sh [image]        (default: nginx-acme:latest)
#   NGINX_TEST_PORT   host port for the HTTP check (default: 8080)
#
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE="${1:-nginx-acme:latest}"
PORT="${NGINX_TEST_PORT:-8080}"
NAME="nginx-acme-smoke"

TMP=$(mktemp -d)
# mktemp gives 0700; the container's nginx workers (uid nginx) must be able to
# traverse into the bind-mounted web root.
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

echo "→ ACME module file present"
docker run --rm "$IMAGE" test -f /usr/lib/nginx/modules/ngx_http_acme_module.so

# `nginx -t` never starts workers, so no ACME request is made by any of the
# config checks below.
echo "→ shipped config parses (load_module, acme_issuer, acme_shared_zone)"
docker run --rm "$IMAGE" nginx -t

echo "→ acme_certificate server block parses"
sed 's/example\.com/smoke.example.test/g' examples/tls.conf.example > "$TMP/conf.d/tls.conf"
docker run --rm -v "$TMP/conf.d:/etc/nginx/conf.d:ro" "$IMAGE" nginx -t

echo "→ HTTP server on port $PORT"
echo "<html><body>Smoke OK</body></html>" > "$TMP/www/index.html"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "$PORT:80" -v "$TMP/www:/var/www/html:ro" "$IMAGE" >/dev/null
for _ in $(seq 1 15); do
    if curl -fsS "http://localhost:$PORT" 2>/dev/null | grep -q "Smoke OK"; then
        break
    fi
    sleep 2
done
curl -fsS "http://localhost:$PORT" | grep -q "Smoke OK" || { echo "✗ HTTP server did not answer"; exit 1; }

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
echo "✓ smoke passed: module loaded, config parses, HTTP served, container healthy"
