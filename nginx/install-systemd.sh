#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SERVICE_FILE="nginx-docker.service"
IMAGE="nginx-acme:latest"

echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  nginx-acme systemd installer          ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}✗ Please run as root (use sudo)${NC}"
    exit 1
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}✗ Docker is not installed${NC}"
    echo "  Please install Docker first: https://docs.docker.com/engine/install/"
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo -e "${RED}✗ Docker is not running${NC}"
    echo "  Start Docker with: sudo systemctl start docker"
    exit 1
fi

echo -e "${BLUE}→${NC} Checking prerequisites..."
echo -e "${GREEN}✓${NC} Docker is installed and running"

if [ ! -f "$SERVICE_FILE" ]; then
    echo -e "${RED}✗ $SERVICE_FILE not found in current directory${NC}"
    echo "  Run this script from the nginx/ directory of the repository."
    exit 1
fi
echo -e "${GREEN}✓${NC} Service file found"

# The image is needed to seed /etc/nginx, so check for it before anything else.
if docker image inspect "$IMAGE" &> /dev/null; then
    echo -e "${GREEN}✓${NC} Found $IMAGE"
else
    echo -e "${RED}✗ $IMAGE not found${NC}"
    echo ""
    echo "Build the image first, from the repository root:"
    echo "  make nginx-build"
    echo ""
    exit 1
fi

# Configuration directory.
#
# The unit mounts the host's /etc/nginx over the one in the image, which hides
# everything the image ships there (mime.types, fastcgi/scgi/uwsgi params, our
# nginx.conf with its load_module line). So seed the host directory from the
# image itself: that guarantees parity instead of a hand-written subset.
echo ""
echo -e "${BLUE}→${NC} Setting up configuration directories..."
if [ ! -d /etc/nginx ]; then
    mkdir -p /etc/nginx
    docker run --rm --entrypoint /bin/sh "$IMAGE" -c 'tar -cf - -C /etc/nginx .' \
        | tar -xf - -C /etc/nginx
    mkdir -p /etc/nginx/conf.d
    echo -e "${GREEN}✓${NC} Seeded /etc/nginx/ from $IMAGE"
else
    echo -e "${YELLOW}!${NC} /etc/nginx/ already exists (not touching it)"
    missing=""
    [ -f /etc/nginx/mime.types ] || missing="$missing mime.types"
    grep -rqs "ngx_http_acme_module.so" /etc/nginx/nginx.conf || missing="$missing load_module(acme)"
    if [ -n "$missing" ]; then
        echo -e "${YELLOW}!${NC} Host config looks incomplete, missing:$missing"
        echo "    The container mounts /etc/nginx read-only over the image's copy,"
        echo "    so anything absent here is absent at runtime. Compare against:"
        echo "      docker run --rm $IMAGE cat /etc/nginx/nginx.conf"
    fi
fi

# Web root
if [ ! -d /var/www/html ]; then
    mkdir -p /var/www/html
    if [ -f html/index.html ]; then
        cp html/index.html /var/www/html/index.html
    else
        echo '<!doctype html><title>nginx-acme</title><h1>nginx-acme is running</h1>' \
            > /var/www/html/index.html
    fi
    echo -e "${GREEN}✓${NC} Created /var/www/html/index.html"
else
    echo -e "${YELLOW}!${NC} /var/www/html/ already exists (skipping)"
fi

# ACME state directory (account key, certificates and private keys).
# The entrypoint chowns it to the nginx user on every start.
if [ ! -d /var/nginx-acme ]; then
    mkdir -p /var/nginx-acme
    chmod 700 /var/nginx-acme
    echo -e "${GREEN}✓${NC} Created /var/nginx-acme/"
else
    echo -e "${YELLOW}!${NC} /var/nginx-acme/ already exists (skipping)"
fi

# Install the unit
echo ""
echo -e "${BLUE}→${NC} Installing systemd service..."
cp "$SERVICE_FILE" /etc/systemd/system/
systemctl daemon-reload
echo -e "${GREEN}✓${NC} Installed $SERVICE_FILE and reloaded systemd"

echo ""
read -p "Enable and start service now? [Y/n]: " start_now

if [[ $start_now =~ ^[Nn]$ ]]; then
    echo ""
    echo -e "${YELLOW}Service installed but not started.${NC}"
    echo ""
    echo "To enable and start:"
    echo "  sudo systemctl enable --now nginx-docker.service"
    exit 0
fi

echo ""
echo -e "${BLUE}→${NC} Enabling and starting service..."
systemctl enable nginx-docker.service
systemctl start nginx-docker.service
echo -e "${GREEN}✓${NC} Started nginx-docker.service"

sleep 3

if ! systemctl is-active --quiet nginx-docker.service; then
    echo ""
    echo -e "${RED}✗ Service failed to start${NC}"
    echo ""
    echo "Check logs with:"
    echo "  sudo systemctl status nginx-docker -l"
    echo "  sudo journalctl -u nginx-docker -n 50"
    exit 1
fi

echo ""
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        Installation Complete! ✓        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Service Commands:${NC}"
echo "  Status:  sudo systemctl status nginx-docker"
echo "  Logs:    sudo journalctl -u nginx-docker -f"
echo "  Reload:  sudo systemctl reload nginx-docker"
echo "  Stop:    sudo systemctl stop nginx-docker"
echo ""
echo -e "${BLUE}Test it:${NC}"
echo "  curl http://localhost"
echo ""
echo -e "${BLUE}Documentation:${NC}"
echo "  See SYSTEMD.md for detailed usage"
echo ""

if command -v curl &> /dev/null; then
    sleep 1
    if curl -sf http://localhost > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} HTTP test successful!"
    else
        echo -e "${YELLOW}!${NC} HTTP test did not return 2xx yet - check the logs above"
    fi
fi
