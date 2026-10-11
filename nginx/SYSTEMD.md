# Running nginx-acme with systemd

Run the nginx-acme container as a systemd service that uses `/etc/nginx` from
your host. Plain `docker run`, no compose.

## Prerequisites

- Docker installed and running
- nginx-acme image built locally: `make nginx-build` (from repository root)

## Installation

### Quick Install (Automated)

```bash
sudo bash install-systemd.sh
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
   sudo systemctl enable --now nginx-docker.service
   ```

4. **Check status:**
   ```bash
   sudo systemctl status nginx-docker.service
   ```

## Directory Structure

The service uses these directories on the host:

```
/etc/nginx/              # nginx configuration (mounted read-only)
├── nginx.conf           # Main configuration, see "Main nginx.conf" below
├── mime.types           # Required: nginx.conf includes it
├── conf.d/              # Your server blocks
└── ...                  # fastcgi/scgi/uwsgi params, seeded from the image

/var/www/                # Web content (mounted read-only)
└── html/                # Default web root

/var/nginx-acme/         # ACME state (mounted read-write, owned by uid 101) - BACK THIS UP
├── letsencrypt/         # account key + certificates, production issuer
└── letsencrypt-staging/ # same, staging issuer
```

Logs are not on disk: the image sends them to stdout/stderr, so they are in
the journal and in `docker logs`, rotated by Docker (10 MB x 3 files).

The container runs as uid 101. The read-only mounts only need to be
world-readable; `/var/nginx-acme` must be owned by uid 101, which the unit
enforces on every start.

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

Whatever you end up with must keep, from the shipped config:

- the first line, `load_module /usr/lib/nginx/modules/ngx_http_acme_module.so;`
- `pid /tmp/nginx.pid;` and the five `*_temp_path /tmp/...` directives: the
  container is read-only and runs as uid 101, `/tmp` is the only writable path
- the `resolver`, `acme_issuer` and `acme_shared_zone` directives in `http`
- the `location = /healthz` block in the default server, which the image's
  health check uses
- no `user` directive: nginx is not root and cannot switch users

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

```bash
sudo systemctl start nginx-docker      # Start
sudo systemctl stop nginx-docker       # Stop
sudo systemctl restart nginx-docker    # Restart
sudo systemctl status nginx-docker     # Check status
sudo systemctl reload nginx-docker     # nginx -t, then HUP (zero downtime)
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
mount a host directory owned by uid 101 at `/var/log/nginx/host`, with your
own logrotate.

## What the unit does

- **Non-root.** The container runs as uid 101 from start to finish. There is
  no root phase, no privilege drop, and nothing in the image is setuid.
- **Read-only root filesystem** with a 64 MB `noexec,nosuid` tmpfs on `/tmp`
  for the pid file and nginx's temp paths. The only persistent writable mount
  is `/var/nginx-acme`.
- **No capabilities** except `NET_BIND_SERVICE`. Under `--network host` the
  container uses the host's privileged-port rule, so binding 80/443 as uid 101
  comes from a file capability the image sets on the nginx binary.
- **No `no-new-privileges`**, deliberately: it disables file capabilities, and
  with it uid 101 could not bind 80/443 on the host network. See *Bridge
  networking* below if you would rather have that flag.
- **Pids limit** of 256.
- **Health check** from the image: busybox `wget` to `http://127.0.0.1/healthz`
  every 30s. Docker reports the status; it does not restart on unhealthy.
- **Log rotation** by Docker's json-file driver, 10 MB x 3 files.
- **Auto-restart** on failure after 10s, graceful stop with a 30s timeout.
- **Unit hardening** (`NoNewPrivileges`, `ProtectSystem=strict`,
  `ProtectHome`) applies to the unit's own process, which is the `docker`
  client. It does not constrain the container; the `docker run` flags do.

### Bridge networking

To run with `-p 80:80 -p 443:443` instead of `--network host`, replace
`--network host` in the unit with the two `-p` flags and add
`--security-opt no-new-privileges`: on a bridge network Docker sets
`ip_unprivileged_port_start=0` inside the container, so uid 101 binds low ports
without any capability and the file capability is unused. Trade-offs: a NAT
hop, and with Docker's default userland proxy, IPv6 clients show up with the
gateway's address in the logs rather than their own.

## Customization

Edit `/etc/systemd/system/nginx-docker.service` to change:

```systemd
Environment="IMAGE=nginx-acme:latest"              # Local image tag
Environment="CONTAINER_NAME=nginx-acme"            # Container name
```

The service uses the locally built image. Rebuild with `make nginx-build` and
`sudo systemctl restart nginx-docker` to update.

## Troubleshooting

### Service won't start

```bash
sudo systemctl status nginx-docker -l
sudo journalctl -u nginx-docker -n 100
sudo docker logs nginx-acme

# Test the host config with the image, as the container would see it
sudo docker run --rm -v /etc/nginx:/etc/nginx:ro nginx-acme:latest nginx -t
```

### Permission denied on /var/nginx-acme

The directory is not owned by uid 101. The unit chowns it on start, so this
only happens if you run the image by hand: `sudo chown 101:101 /var/nginx-acme`.

### bind() to 0.0.0.0:80 failed (13: Permission denied)

You added `--security-opt no-new-privileges` while keeping `--network host`.
Remove one of the two; see *Bridge networking*.

### Port already in use

```bash
sudo ss -tlnp | grep -E ':80|:443'
sudo systemctl stop apache2  # or nginx
```

## Upgrading

```bash
cd /path/to/docker-images
make nginx-build
sudo systemctl restart nginx-docker
```

## Backup & Restore

```bash
sudo tar czf acme-backup.tar.gz /var/nginx-acme   # account key + private keys
sudo tar xzf acme-backup.tar.gz -C /               # restore (ownership is in the archive)
sudo tar czf nginx-config-backup.tar.gz /etc/nginx
```

## Uninstall

```bash
sudo systemctl disable --now nginx-docker
sudo rm /etc/systemd/system/nginx-docker.service
sudo systemctl daemon-reload
docker rm -f nginx-acme

# Optional: remove ACME certificates (WARNING: this deletes all certificates and the account key)
# sudo rm -rf /var/nginx-acme
```

## See Also

- [nginx Documentation](http://nginx.org/en/docs/)
- [nginx-acme Module](https://github.com/nginx/nginx-acme)
- [nginx-unprivileged image](https://github.com/nginx/docker-nginx-unprivileged)
- [systemd Service Documentation](https://www.freedesktop.org/software/systemd/man/systemd.service.html)
