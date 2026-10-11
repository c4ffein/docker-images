# nginx with the ACME module, non-root

nginx on Alpine with [`ngx_http_acme_module`](https://github.com/nginx/nginx-acme),
which obtains and renews Let's Encrypt certificates from inside nginx itself —
no certbot, no cron job, no reload dance. The container runs as an unprivileged
user with a read-only root filesystem and no capabilities.

## What this image is

Base: [`nginxinc/nginx-unprivileged`](https://hub.docker.com/r/nginxinc/nginx-unprivileged),
slim Alpine variant. That is nginx and nothing else — no njs, xslt, geoip or
image-filter modules, no curl — and the whole process tree runs as uid 101.

The unprivileged image does not ship the ACME module, so this image adds:

- `nginx-module-acme`, installed from the same signed nginx.org apk repository
  the base image got nginx from. Nothing is compiled. The build fails if the
  package or module file is missing.
- a `nginx.conf` that loads the module, declares production + staging issuers,
  and keeps the pid and temp files under `/tmp` so the rest of the filesystem
  can be read-only
- a `HEALTHCHECK` (busybox `wget` against a loopback-only `/healthz`)
- a file capability on the nginx binary so uid 101 can bind 80/443 even with
  `--network host` (see *Hardening*)
- a build-time `nginx -t`

Base image and ACME package version are overridable:
`docker build --build-arg NGINX_IMAGE=... --build-arg ACME_VERSION=... .`
The two must match: the apk is versioned `<nginx>.<acme>-r<release>` and
depends on the exact nginx version. When bumping, take `ACME_VERSION` from
[docker-nginx's Dockerfile](https://github.com/nginx/docker-nginx/blob/master/mainline/alpine/Dockerfile).

## Quick start

From the repository root:

```bash
make nginx-build      # build nginx-acme:latest
make nginx-test       # smoke tests, see below
make nginx-run        # docker run with ports 80/443, html/ and conf.d/ mounted
```

`make nginx-run` is the plain `docker run` you would write by hand, with the
hardening flags from the Makefile's `NGINX_HARDENING`. No docker compose.

```bash
make nginx-logs       # follow logs
make nginx-reload     # nginx -t, then HUP
make nginx-stop       # remove the container, keep the ACME state volume
```

## Enabling HTTPS

1. Point your domain's A/AAAA records at the host, and make sure port 80 is
   reachable from the internet — the HTTP-01 challenge needs it.
2. Copy the example and set your domain:

   ```bash
   cp examples/tls.conf.example conf.d/example.com.conf
   sed -i 's/example\.com/yourdomain.tld/g' conf.d/example.com.conf
   ```

3. Start with the **staging** issuer (the example already does). Staging
   certificates are untrusted by browsers, but its rate limits are far looser
   than production, so a misconfiguration costs nothing.
4. Reload and watch the log:

   ```bash
   make nginx-reload
   make nginx-logs
   ```

5. Once you see a certificate issued, switch `acme_certificate letsencrypt_staging;`
   to `acme_certificate letsencrypt;` and reload again.

The minimal shape of an ACME-managed server block:

```nginx
server {
    listen 443 ssl;
    server_name example.com;

    acme_certificate letsencrypt;
    ssl_certificate     $acme_certificate;
    ssl_certificate_key $acme_certificate_key;
    ssl_certificate_cache max=2;
}
```

Renewal is automatic; nginx keeps the certificate in the `ngx_acme_shared`
shared memory zone and refreshes it in the background.

## Persistence — read this

The ACME account key, the issued certificates and their private keys live under
`state_path`, which this image sets to `/var/nginx-acme/<issuer>`. **That
directory must be persisted.** If it is lost, every restart registers a new ACME
account and re-issues every certificate, which burns Let's Encrypt rate limits
quickly (50 certificates per registered domain per week).

`make nginx-run` maps it to the `nginx-acme-state` named volume, which Docker
initialises with the image's ownership (uid 101). The systemd unit bind-mounts
the host's `/var/nginx-acme` and chowns it to 101 on every start. If you mount
your own directory, it must be owned by uid 101: the container cannot chown it.

## Hardening

The container is meant to run with these flags, which `make nginx-run`, the
systemd unit and both test scripts all use:

| Flag | Why |
|------|-----|
| `--read-only` | nothing on the image filesystem is written at runtime |
| `--tmpfs /tmp:rw,noexec,nosuid,size=64m` | pid file and nginx temp paths |
| `--cap-drop ALL --cap-add NET_BIND_SERVICE` | uid 101 needs nothing but binding 80/443 |
| `--security-opt no-new-privileges` | bridge networking only, see below |
| `--pids-limit 256` | fork bomb ceiling |

**Binding 80/443 as uid 101.** On a bridge network Docker sets
`ip_unprivileged_port_start=0` inside the container, so no capability is
needed and `no-new-privileges` can be on. With `--network host` the container
uses the host's rule instead, so the image carries
`cap_net_bind_service=+ep` as a file capability on the nginx binary. File
capabilities are disabled by `no-new-privileges`, so the systemd unit, which
uses host networking, leaves that one flag out. Pick one: host networking
without `no-new-privileges`, or bridge networking with it.

## Paths

| Path | Purpose |
|------|---------|
| `/var/www/html` | web root of the default server |
| `/etc/nginx/conf.d` | your server blocks (`include`d last) |
| `/etc/nginx/nginx.conf` | main config, override to replace it entirely (keep `pid /tmp/nginx.pid`, the temp paths and `/healthz`) |
| `/var/nginx-acme` | **ACME state — persist this** (mode 0700, owned by uid 101) |
| `/tmp` | pid file and temp paths; must be a writable tmpfs |
| `/var/log/nginx` | logs; symlinked to stdout/stderr |

## Configuration notes

- **Resolver.** The ACME module requires a `resolver` in the `http` block —
  nginx does not use the system resolver for runtime lookups. This config lists
  `1.1.1.1` (Cloudflare), `8.8.8.8` (Google) and `9.9.9.9` (Quad9): three
  independent operators, so one outage does not stop renewal. Docker's embedded
  DNS at `127.0.0.11` is deliberately not used, because it does not exist when
  the container runs with `--network host`, which is how the systemd unit runs
  it. Note that Quad9 filters known-malicious domains; irrelevant for reaching
  an ACME server, but it is a behavioural difference from the other two.
- **Contact address.** Commented out, and worth leaving that way: Let's Encrypt
  stopped sending expiration notification emails on 2025-06-04, specifically to
  avoid retaining subscriber email addresses, so the field buys nothing there.
  If you do want one, set it in your deployment's config rather than in this
  repo — otherwise anyone deploying a copy registers an ACME account under your
  address.
- **Challenge type.** HTTP-01 by default. `tls-alpn-01` is available via
  `challenge tls-alpn;` inside the issuer block.
- **No `user` directive.** nginx is not root, so it cannot switch users; the
  directive would only produce a warning.

## Deployment as a systemd service

See [SYSTEMD.md](SYSTEMD.md). Short version: `sudo bash install-systemd.sh`
from this directory, after `make nginx-build`.

## Debugging

```bash
make nginx-logs                        # ACME errors show up here
docker exec nginx-acme nginx -t        # validate config
make nginx-reload                      # apply config changes
docker inspect -f '{{.State.Health.Status}}' nginx-acme
docker exec nginx-acme ls -la /var/nginx-acme
docker exec -it nginx-acme sh          # busybox shell, uid 101
```

Common failures:

- **`nginx: [emerg] module ... not found`** — the base image no longer ships
  nginx from nginx.org, or the ACME apk is gone. The build itself asserts this,
  so a successful build rules it out.
- **`bind() to 0.0.0.0:80 failed (13: Permission denied)`** — you combined
  `--network host` with `no-new-privileges`, or ran a different image's nginx
  binary. See *Hardening*.
- **`mkdir() "/var/nginx-acme/..." failed (30: Read-only file system)`** —
  nothing is mounted at `/var/nginx-acme`. The module creates its issuer
  directory there on startup, and the image's filesystem is read-only. Mount a
  volume; see *Persistence*.
- **`open() "/var/nginx-acme/..." failed (13: Permission denied)`** — the
  mounted state directory is not owned by uid 101.
- **Challenge fails** — port 80 is not reachable from the internet, DNS does not
  resolve to this host, or something else answers `/.well-known/acme-challenge/`
  first. The module handles that location itself; do not add your own.
- **Rate limited** — you lost `/var/nginx-acme` between restarts. See
  *Persistence* above, and test against the staging issuer.

## Publishing

```bash
make nginx-push DOCKER_REGISTRY=youruser
```

## Testing

```bash
make nginx-test      # fast: non-root, module present, config parses, HTTP serves, healthy
make nginx-e2e       # real certificate issuance, offline, ~1 minute
```

`make nginx-test` runs `test/run-smoke.sh`: the container runs as uid 101, the
module file exists, `nginx -t` loads it, an `acme_certificate` server block
parses, HTTP is served from a mounted web root under the full hardening flags,
`/healthz` is refused from outside, and the container's health check turns
green.

`make nginx-e2e` runs `test/run-e2e.sh`, which stands up
[Pebble](https://github.com/letsencrypt/pebble) — Let's Encrypt's own test ACME
server — next to this image with plain `docker run` on a private network, and
makes nginx actually obtain and serve a certificate. No domain, no internet, no
Let's Encrypt account involved.

It matters that the drop-in at `test/conf.d/e2e.conf` is loaded by the **real
`nginx.conf` from the image**, unmodified, under the real hardening flags. So
the test fails if the shipped config, the module, the base image or the flags
drift apart — which a `nginx -t` check cannot detect.

Add `--keep` to leave the stack up and poke at it:

```bash
bash nginx/test/run-e2e.sh --keep
docker logs -f nginx-acme-e2e-nginx
```

The Makefile invokes both scripts through `bash`, so they work whether or not
the executable bit survived a checkout.

## CI

`.github/workflows/build-nginx.yml` builds for `linux/amd64` and `linux/arm64`
and runs `make nginx-test` on each. A separate job runs `make nginx-e2e` on
amd64. CI only adds the build cache and the arm64 build; the checks themselves
are the Makefile's, so what passes locally is what passes in CI.
