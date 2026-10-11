#!/bin/sh
set -e

# The ACME module stores the account key, issued certificates and private keys
# under state_path (see nginx.conf). Workers run as `nginx`, so that directory
# must be writable by that user and readable by nobody else.
ACME_STATE_DIR="${ACME_STATE_DIR:-/var/nginx-acme}"

if [ "$(id -u)" = "0" ]; then
    mkdir -p "$ACME_STATE_DIR"
    chown -R nginx:nginx "$ACME_STATE_DIR"
    chmod 700 "$ACME_STATE_DIR"
fi

# Fail fast with a readable error instead of a half-started container.
echo "Testing nginx configuration..."
nginx -t

exec "$@"
