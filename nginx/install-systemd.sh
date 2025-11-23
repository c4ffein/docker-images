#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if service file exists
SERVICE_FILE="nginx-docker.service"
if [ ! -f "$SERVICE_FILE" ]; then
    echo -e "${RED}✗ $SERVICE_FILE not found in current directory${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} Service file found"

# Copy service file
echo ""
echo -e "${BLUE}→${NC} Installing systemd service..."
cp "$SERVICE_FILE" /etc/systemd/system/
echo -e "${GREEN}✓${NC} Copied $SERVICE_FILE to /etc/systemd/system/"

# Reload systemd
systemctl daemon-reload
echo -e "${GREEN}✓${NC} Reloaded systemd"

# Create /etc/nginx if it doesn't exist
echo ""
echo -e "${BLUE}→${NC} Setting up configuration directories..."
if [ ! -d /etc/nginx ]; then
    mkdir -p /etc/nginx/conf.d
    echo -e "${GREEN}✓${NC} Created /etc/nginx/"

    # Create minimal nginx.conf
    cat > /etc/nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;

    sendfile on;
    keepalive_timeout 65;
    gzip on;

    # Include server configs
    include /etc/nginx/conf.d/*.conf;
}
EOF
    echo -e "${GREEN}✓${NC} Created /etc/nginx/nginx.conf"
else
    echo -e "${YELLOW}!${NC} /etc/nginx/ already exists (skipping)"
fi

# Create /var/www if it doesn't exist
if [ ! -d /var/www/html ]; then
    mkdir -p /var/www/html

    # Create simple index.html
    cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>nginx-acme is running</title>
    <style>
        body {
            font-family: system-ui, -apple-system, sans-serif;
            max-width: 800px;
            margin: 100px auto;
            padding: 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
        }
        .container {
            background: rgba(255,255,255,0.1);
            padding: 40px;
            border-radius: 10px;
            backdrop-filter: blur(10px);
        }
        h1 { margin: 0 0 20px 0; }
        code {
            background: rgba(0,0,0,0.2);
            padding: 2px 8px;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 nginx-acme is running!</h1>
        <p>Your nginx instance with ACME module support is up and running.</p>
        <p>Configuration: <code>/etc/nginx/nginx.conf</code></p>
        <p>Manage: <code>sudo systemctl status nginx-docker</code></p>
    </div>
</body>
</html>
EOF
    echo -e "${GREEN}✓${NC} Created /var/www/html/index.html"
else
    echo -e "${YELLOW}!${NC} /var/www/html/ already exists (skipping)"
fi

# Create log directory
if [ ! -d /var/log/nginx ]; then
    mkdir -p /var/log/nginx
    echo -e "${GREEN}✓${NC} Created /var/log/nginx/"
fi

# Create ACME directory
if [ ! -d /var/nginx-acme ]; then
    mkdir -p /var/nginx-acme
    echo -e "${GREEN}✓${NC} Created /var/nginx-acme/"
else
    echo -e "${YELLOW}!${NC} /var/nginx-acme/ already exists (skipping)"
fi

# Check if the local image exists
echo ""
echo -e "${BLUE}→${NC} Checking for local Docker image..."
if docker image inspect nginx-acme:latest &> /dev/null; then
    echo -e "${GREEN}✓${NC} Found nginx-acme:latest image"
else
    echo -e "${RED}✗ nginx-acme:latest image not found${NC}"
    echo ""
    echo "Build the image first with:"
    echo "  cd /home/debian/docker-images"
    echo "  make nginx-build"
    echo ""
    exit 1
fi

# Ask if user wants to enable and start now
echo ""
read -p "Enable and start service now? [Y/n]: " start_now

if [[ ! $start_now =~ ^[Nn]$ ]]; then
    echo ""
    echo -e "${BLUE}→${NC} Enabling and starting service..."

    systemctl enable nginx-docker.service
    echo -e "${GREEN}✓${NC} Enabled nginx-docker.service"

    systemctl start nginx-docker.service
    echo -e "${GREEN}✓${NC} Started nginx-docker.service"

    sleep 3

    # Check status
    if systemctl is-active --quiet nginx-docker.service; then
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

        # Try to test the service
        if command -v curl &> /dev/null; then
            sleep 1
            if curl -sf http://localhost > /dev/null 2>&1; then
                echo -e "${GREEN}✓${NC} HTTP test successful!"
            fi
        fi
    else
        echo ""
        echo -e "${RED}✗ Service failed to start${NC}"
        echo ""
        echo "Check logs with:"
        echo "  sudo systemctl status nginx-docker -l"
        echo "  sudo journalctl -u nginx-docker -n 50"
        exit 1
    fi
else
    echo ""
    echo -e "${YELLOW}Service installed but not started.${NC}"
    echo ""
    echo "To enable and start:"
    echo "  sudo systemctl enable nginx-docker.service"
    echo "  sudo systemctl start nginx-docker.service"
fi
