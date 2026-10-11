#!/usr/bin/env bash
#
# End-to-end ACME test: nginx obtains a real certificate from a local Pebble
# ACME server and serves it. No internet, no domain, no Let's Encrypt account.
#
#   pebble        ACME server (a real ACME implementation, not a mock)
#   challtestsrv  DNS that answers every query with nginx's address, so Pebble
#                 validates the challenge against our container
#   nginx         the image under test, running its shipped config plus the
#                 conf.d drop-in in test/conf.d, under the same hardening
#                 flags as production
#
# Static addresses because Pebble needs to be reachable by IP from nginx before
# any DNS is configured.
#
# Usage: bash nginx/test/run-e2e.sh [--keep]
#   --keep   leave the stack running for inspection
#
set -euo pipefail

cd "$(dirname "$0")"

KEEP="${1:-}"
TIMEOUT_SECONDS=120

IMAGE="nginx-acme:latest"
PEBBLE_VERSION="2.10.1"
NET="nginx-acme-e2e"
SUBNET="10.30.50.0/24"
IP_PEBBLE="10.30.50.2"
IP_DNS="10.30.50.3"
IP_NGINX="10.30.50.4"
C_PEBBLE="$NET-pebble"
C_DNS="$NET-challtestsrv"
C_NGINX="$NET-nginx"
# The module creates its issuer directory under /var/nginx-acme on startup;
# with --read-only that needs a mount, exactly as in production.
VOL_STATE="$NET-state"

# Keep in sync with NGINX_HARDENING in the Makefile and nginx-docker.service.
HARDENING=(
    --read-only
    --tmpfs /tmp:rw,noexec,nosuid,size=64m
    --cap-drop ALL
    --cap-add NET_BIND_SERVICE
    --security-opt no-new-privileges
    --pids-limit 256
)

teardown() {
    docker rm -f "$C_NGINX" "$C_DNS" "$C_PEBBLE" >/dev/null 2>&1 || true
    docker network rm "$NET" >/dev/null 2>&1 || true
    docker volume rm "$VOL_STATE" >/dev/null 2>&1 || true
}

cleanup() {
    local rc=$?
    if [ "$KEEP" = "--keep" ]; then
        echo "--keep given, leaving the stack up. Tear down with:"
        echo "  docker rm -f $C_NGINX $C_DNS $C_PEBBLE && docker network rm $NET && docker volume rm $VOL_STATE"
        return
    fi
    if [ $rc -ne 0 ]; then
        echo
        echo "=== nginx logs ==="
        docker logs "$C_NGINX" 2>&1 || true
        echo "=== pebble logs ==="
        docker logs "$C_PEBBLE" 2>&1 || true
    fi
    teardown
}
trap cleanup EXIT

echo "→ Building the image..."
docker build -t "$IMAGE" ..

echo "→ Starting the test stack..."
teardown
docker network create --subnet "$SUBNET" "$NET" >/dev/null

docker run -d --name "$C_PEBBLE" --network "$NET" --ip "$IP_PEBBLE" \
    -e PEBBLE_VA_NOSLEEP=1 \
    "ghcr.io/letsencrypt/pebble:$PEBBLE_VERSION" -dnsserver "$IP_DNS:8053" >/dev/null

docker run -d --name "$C_DNS" --network "$NET" --ip "$IP_DNS" \
    "ghcr.io/letsencrypt/pebble-challtestsrv:$PEBBLE_VERSION" \
    -defaultIPv6 "" -defaultIPv4 "$IP_NGINX" >/dev/null

# Port 443 exposed so the test script can do the TLS handshake from the host.
docker run -d --name "$C_NGINX" --network "$NET" --ip "$IP_NGINX" "${HARDENING[@]}" \
    -p 8443:443 \
    -v "$PWD/conf.d:/etc/nginx/conf.d:ro" \
    -v "$VOL_STATE:/var/nginx-acme" \
    "$IMAGE" >/dev/null

# Until the certificate is issued, $acme_certificate is empty and nginx logs
# `cannot load certificate "/etc/nginx/"` on each handshake attempt. That is
# expected noise from this polling loop, not a failure.
echo "→ Waiting for nginx to obtain a certificate from Pebble (up to ${TIMEOUT_SECONDS}s)..."
deadline=$((SECONDS + TIMEOUT_SECONDS))
pem=""
while [ $SECONDS -lt $deadline ]; do
    pem=$(openssl s_client -connect 127.0.0.1:8443 -servername e2e.test </dev/null 2>/dev/null \
        | openssl x509 2>/dev/null || true)
    case "$(printf '%s' "$pem" | openssl x509 -noout -issuer 2>/dev/null)" in
        *Pebble*) break ;;
    esac
    pem=""
    sleep 3
done

if [ -z "$pem" ]; then
    echo "✗ no Pebble-issued certificate after ${TIMEOUT_SECONDS}s"
    exit 1
fi

printf '%s' "$pem" | openssl x509 -noout -issuer -subject -ext subjectAltName | sed 's/^/    /'

# Pebble issues certificates with an empty subject (no CN) and the name only
# in the SAN, like Let's Encrypt does since 2025, so check the SAN.
case "$(printf '%s' "$pem" | openssl x509 -noout -ext subjectAltName 2>/dev/null)" in
    *DNS:e2e.test*) ;;
    *) echo "✗ certificate is not for e2e.test"; exit 1 ;;
esac

echo "→ Checking the served content over TLS..."
body=$(curl -sk --resolve e2e.test:8443:127.0.0.1 https://e2e.test:8443/)
[ "$body" = "e2e ok" ] || { echo "✗ unexpected body: $body"; exit 1; }

echo "→ Checking the ACME state was persisted..."
docker exec "$C_NGINX" sh -c 'ls /var/nginx-acme/pebble >/dev/null' \
    || { echo "✗ state_path is empty - certificates would not survive a restart"; exit 1; }

echo
echo "✓ E2E passed: certificate issued by Pebble, served by non-root nginx, state persisted"
