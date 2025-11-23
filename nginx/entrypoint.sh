#!/bin/sh
set -e

# Create ACME directory (only writable mount)
mkdir -p /var/nginx-acme/certs
mkdir -p /var/nginx-acme/acme-challenge

# Set proper permissions for ACME directory
chown -R nginx:nginx /var/nginx-acme

# Test nginx configuration
echo "Testing nginx configuration..."
nginx -t

# Execute the main command
exec "$@"
