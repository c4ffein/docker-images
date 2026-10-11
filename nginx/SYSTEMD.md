# Running nginx-acme with systemd

Run the nginx-acme Docker container as a systemd service that uses `/etc/nginx` from your host.

## Prerequisites

- Docker installed and running
- nginx-acme image built locally: `make nginx-build` (from repository root)

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
├── nginx.conf           # Main configuration, must keep the load_module line
├── mime.types           # Required: nginx.conf includes it
├── conf.d/              # Your server blocks
└── ...                  # fastcgi/scgi/uwsgi params, seeded from the image

/var/www/                # Web content (mounted read-only)
└── html/                # Default web root

/var/nginx-acme/         # ACME state (mounted read-write) - BACK THIS UP
├── letsencrypt/         # account key + certificates, production issuer
└── letsencrypt-staging/ # same, staging issuer
```

Logs are not on disk: the image sends them to stdout/stderr, so they are in
the journal and in `docker logs`, rotated by Docker (10 MB x 3 files).

## Configuration

### Main nginx.conf

The unit mounts the host's `/etc/nginx` **over** the image's, which hides
everything the image ships there: `mime.types`, the fastcgi/scgi/uwsgi param
files, and the `nginx.conf` with its `load_module` line for the ACME module. A
hand-written host config that only contains `nginx.conf` will fail to start,
because `include /etc/nginx/mime.types` refers to a file that no longer exists.

So do not write it from scratch. `install-systemd.sh` seeds `/etc/nginx` from
the image itself. To do it by hand, or to refresh it later:

```bash
sudo docker run --rm --entrypoint /bin/sh nginx-acme:latest \
    -c 'tar -cf - -C /etc/nginx .' | sudo tar -xf - -C /etc/nginx
```

Whatever you end up with must keep the first line of the shipped config:

```nginx
load_module /usr/lib/nginx/modules/ngx_http_acme_module.so;
```

and the `resolver`, `acme_issuer` and `acme_shared_zone` directives in `http`.
Check the host copy against the image's at any time:

```bash
sudo docker run --rm nginx-acme:latest cat /etc/nginx/nginx.conf | diff - /etc/nginx/nginx.conf
```

### Server Blocks

Add server configurations in `/etc/nginx/conf.d/`:

```bash
sudo vim /etc/nginx/conf.d/example.com.conf
```

Plain HTTP:
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

HTTPS with an automatic certificate (see `examples/tls.conf.example` for the
full version, and start with `letsencrypt_staging` while you validate DNS):
```nginx
server {
    listen 443 ssl;
    server_name example.com www.example.com;
    root /var/www/html;

    acme_certificate letsencrypt;
    ssl_certificate     $acme_certificate;
    ssl_certificate_key $acme_certificate_key;
    ssl_certificate_cache max=2;
}
```

A listener on port 80 for the same names must stay reachable from the internet:
that is where the HTTP-01 challenge is answered, by the module itself.

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
# Systemd journal (same content as docker logs)
sudo journalctl -u nginx-docker -f

# Docker logs - ACME issuance and renewal errors show up here
sudo docker logs -f nginx-acme
```

If you need log files on disk (fail2ban, goaccess...), do not bind-mount a
host directory over `/var/log/nginx`: that hides the image's stdout/stderr
symlinks and nothing rotates the resulting files. Instead, add
`access_log /var/log/nginx/host/access.log main;` to your server blocks and
mount a host directory at `/var/log/nginx/host`, with your own logrotate.

## Features

The service includes:

✅ **Health check** - the image's `HEALTHCHECK` curls `http://127.0.0.1/` every 30s
✅ **Log rotation** - Docker json-file driver, max 10MB per file, 3 files kept
✅ **Auto-restart** - Restarts on failure with 10s delay
✅ **Graceful shutdown** - 30s timeout for clean stops
✅ **Security hardening** - NoNewPrivileges, ProtectSystem, etc. (on the docker client process)
✅ **ACME persistence** - account key and certificates bind-mounted from `/var/nginx-acme`
✅ **Host networking** - Direct port access, no NAT overhead

## Customization

### Environment Variables

Edit `/etc/systemd/system/nginx-docker.service` to change:

```systemd
Environment="IMAGE=nginx-acme:latest"              # Local image tag
Environment="CONTAINER_NAME=nginx-acme"            # Container name
```

Note: The service uses the locally built image. Rebuild with `make nginx-build` to update.

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
  nginx-acme:latest nginx -t
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
# Rebuild the image with latest changes
cd /path/to/docker-images
make nginx-build

# Restart service to use new image
sudo systemctl restart nginx-docker
```

The service always uses the locally built `nginx-acme:latest` image.

## Backup & Restore

### Backup ACME Certificates
```bash
sudo tar czf acme-backup.tar.gz /var/nginx-acme   # account key + private keys
```

### Restore ACME Certificates
```bash
sudo tar xzf acme-backup.tar.gz -C /
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

# Optional: Remove container
docker rm -f nginx-acme

# Optional: Remove ACME certificates (WARNING: This deletes all certificates!)
# sudo rm -rf /var/nginx-acme
```

## Security

The service includes security hardening:

- **Read-only mounts** for config and web content
- **NoNewPrivileges**, **ProtectSystem**, **ProtectHome** on the unit's own
  process (the `docker` client); they do not constrain the container itself
- **Log rotation** by Docker prevents disk filling

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
