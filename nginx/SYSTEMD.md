# Running nginx-acme with systemd

Run the nginx-acme Docker container as a systemd service that uses `/etc/nginx` from your host.

## Prerequisites

- Docker installed and running
- nginx-acme image available: `docker pull nginx/nginx-acme:latest` (or build locally)

## Installation

### Quick Install (Automated)

```bash
sudo ./install-systemd.sh
```

### Manual Install

1. **Copy the service file:**
   ```bash
   sudo cp nginx-docker.service /etc/systemd/system/
   ```

2. **Reload systemd:**
   ```bash
   sudo systemctl daemon-reload
   ```

3. **Enable and start the service:**
   ```bash
   sudo systemctl enable nginx-docker.service
   sudo systemctl start nginx-docker.service
   ```

4. **Check status:**
   ```bash
   sudo systemctl status nginx-docker.service
   ```

## Directory Structure

The service uses these directories on the host:

```
/etc/nginx/              # nginx configuration (mounted read-only)
├── nginx.conf           # Main configuration
├── conf.d/              # Additional server configs
└── acme/                # ACME certificates (managed by container)

/var/www/                # Web content (mounted read-only)
└── html/                # Default web root

/var/log/nginx/          # nginx logs (optional, also in Docker logs)
```

## Configuration

### Main nginx.conf

Create or update `/etc/nginx/nginx.conf`:

```nginx
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

    # Include all conf.d configs
    include /etc/nginx/conf.d/*.conf;
}
```

### Server Blocks

Add server configurations in `/etc/nginx/conf.d/`:

```bash
sudo vim /etc/nginx/conf.d/example.com.conf
```

Example:
```nginx
server {
    listen 80;
    server_name example.com www.example.com;
    root /var/www/html;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

## Management

### Basic Commands
```bash
sudo systemctl start nginx-docker      # Start
sudo systemctl stop nginx-docker       # Stop
sudo systemctl restart nginx-docker    # Restart
sudo systemctl status nginx-docker     # Check status
```

### Reload Configuration (Zero Downtime)
```bash
# Test config first
sudo docker exec nginx-acme nginx -t

# Reload if OK
sudo systemctl reload nginx-docker
```

### View Logs
```bash
# Systemd journal
sudo journalctl -u nginx-docker -f

# Docker logs
sudo docker logs -f nginx-acme

# nginx log files
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

## Features

The service includes:

✅ **Health checks** - Automatic config validation every 30s
✅ **Log rotation** - Max 10MB per file, 3 files kept
✅ **Auto-restart** - Restarts on failure with 10s delay
✅ **Graceful shutdown** - 30s timeout for clean stops
✅ **Security hardening** - NoNewPrivileges, ProtectSystem, etc.
✅ **ACME persistence** - Certificates in named volume
✅ **Host networking** - Direct port access, no NAT overhead

## Customization

### Environment Variables

Edit `/etc/systemd/system/nginx-docker.service` to change:

```systemd
Environment="IMAGE=nginx/nginx-acme:latest"        # Image to use
Environment="CONTAINER_NAME=nginx-acme"            # Container name
```

### Disable Auto-Updates

Comment out the pull line to control updates manually:

```systemd
# ExecStartPre=-/usr/bin/docker pull ${IMAGE}
```

### Use Bridge Networking

Replace `--network host` with port mapping:

```systemd
ExecStart=/usr/bin/docker run --rm \
    --name ${CONTAINER_NAME} \
    -p 80:80 \
    -p 443:443 \
    # ... rest of options
```

## Troubleshooting

### Service won't start

```bash
# Check systemd status
sudo systemctl status nginx-docker -l

# Check Docker logs
sudo docker logs nginx-acme

# Test config manually
sudo docker run --rm \
  -v /etc/nginx:/etc/nginx:ro \
  nginx/nginx-acme:latest nginx -t
```

### Configuration errors

```bash
# Test before reloading
sudo docker exec nginx-acme nginx -t

# View error details
sudo docker logs nginx-acme --tail 50
```

### Port already in use

```bash
# Check what's using port 80/443
sudo ss -tlnp | grep -E ':80|:443'

# Stop conflicting service
sudo systemctl stop apache2  # or nginx
```

### Container keeps restarting

```bash
# Disable auto-restart temporarily
sudo systemctl stop nginx-docker

# Check logs
sudo journalctl -u nginx-docker -n 100

# Fix config and restart
sudo systemctl start nginx-docker
```

## Upgrading

```bash
# Pull new image
sudo docker pull nginx/nginx-acme:latest

# Restart service (uses new image)
sudo systemctl restart nginx-docker
```

Or enable auto-pull (already enabled by default) and just restart.

## Backup & Restore

### Backup ACME Certificates
```bash
docker run --rm \
  -v nginx-acme-certs:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/acme-backup.tar.gz /data
```

### Restore ACME Certificates
```bash
docker run --rm \
  -v nginx-acme-certs:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/acme-backup.tar.gz -C /
```

### Backup nginx Config
```bash
sudo tar czf nginx-config-backup.tar.gz /etc/nginx
```

## Uninstall

```bash
# Stop and disable
sudo systemctl stop nginx-docker
sudo systemctl disable nginx-docker

# Remove service file
sudo rm /etc/systemd/system/nginx-docker.service

# Reload systemd
sudo systemctl daemon-reload

# Optional: Remove container and volumes
docker rm -f nginx-acme
docker volume rm nginx-acme-certs
```

## Security

The service includes security hardening:

- **Read-only mounts** for config and web content
- **NoNewPrivileges** prevents privilege escalation
- **ProtectSystem** makes most of filesystem read-only
- **ProtectHome** hides home directories
- **Log rotation** prevents disk filling

For additional security:
- Use Docker user namespaces
- Configure SELinux/AppArmor policies
- Enable audit logging
- Restrict container capabilities

## Performance

The service uses `--network host` for best performance:
- No NAT/bridge overhead
- Direct kernel networking
- Lower latency
- Higher throughput

For Docker benchmark comparisons, see: https://www.nginx.com/blog/docker-networking/

## See Also

- [nginx Documentation](http://nginx.org/en/docs/)
- [nginx-acme Module](https://github.com/nginx/nginx-acme)
- [systemd Service Documentation](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
