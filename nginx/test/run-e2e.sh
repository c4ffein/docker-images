#!/usr/bin/env bash
#
# End-to-end ACME test: nginx obtains a real certificate from a local Pebble
# ACME server and serves it. No internet, no domain, no Let's Encrypt account.
#
# Usage: nginx/test/run-e2e.sh [--keep]
#   --keep   leave the stack running for inspection
#
set -euo pipefail

cd "$(dirname "$0")"

COMPOSE=(docker compose -f docker-compose.e2e.yml -p nginx-acme-e2e)
KEEP="${1:-}"
TIMEOUT_SECONDS=120

cleanup() {
    local rc=$?
    if [ "$KEEP" = "--keep" ]; then
        echo "--keep given, leaving the stack up. Tear down with:"
        echo "  ${COMPOSE[*]} down -v"
        return
    fi
    if [ $rc -ne 0 ]; then
        echo
        echo "=== nginx logs ==="
        "${COMPOSE[@]}" logs --no-color nginx || true
        echo "=== pebble logs ==="
        "${COMPOSE[@]}" logs --no-color pebble || true
    fi
    "${COMPOSE[@]}" down -v --remove-orphans >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "→ Building and starting the test stack..."
"${COMPOSE[@]}" up -d --build

echo "→ Waiting for nginx to obtain a certificate from Pebble (up to ${TIMEOUT_SECONDS}s)..."
deadline=$((SECONDS + TIMEOUT_SECONDS))
cert=""
while [ $SECONDS -lt $deadline ]; do
    cert=$(openssl s_client -connect 127.0.0.1:8443 -servername e2e.test </dev/null 2>/dev/null \
        | openssl x509 -noout -issuer -subject 2>/dev/null || true)
    case "$cert" in
        *Pebble*) break ;;
    esac
    cert=""
    sleep 3
done

if [ -z "$cert" ]; then
    echo "✗ no Pebble-issued certificate after ${TIMEOUT_SECONDS}s"
    exit 1
fi

echo "$cert" | sed 's/^/    /'

case "$cert" in
    *CN=e2e.test*|*CN\ =\ e2e.test*) ;;
    *) echo "✗ certificate is not for e2e.test"; exit 1 ;;
esac

echo "→ Checking the served content over TLS..."
body=$(curl -sk --resolve e2e.test:8443:127.0.0.1 https://e2e.test:8443/)
[ "$body" = "e2e ok" ] || { echo "✗ unexpected body: $body"; exit 1; }

echo "→ Checking the ACME state was persisted..."
"${COMPOSE[@]}" exec -T nginx sh -c 'ls /var/nginx-acme/pebble >/dev/null' \
    || { echo "✗ state_path is empty - certificates would not survive a restart"; exit 1; }

echo
echo "✓ E2E passed: certificate issued by Pebble, served by nginx, state persisted"
