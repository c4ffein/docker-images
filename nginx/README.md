# nginx with the ACME module

nginx on Alpine with [`ngx_http_acme_module`](https://github.com/nginx/nginx-acme),
which obtains and renews Let's Encrypt certificates from inside nginx itself —
no certbot, no cron job, no reload dance.

## What this image is

Since nginx 1.29 the official `nginx:mainline-alpine` image ships the ACME
module (`nginx-module-acme`), so this image does **not** compile anything. It is
the upstream image plus:

- a `nginx.conf` that loads the module and declares production + staging issuers
- an entrypoint that prepares the ACME state directory and fails fast on a bad config
- a `HEALTHCHECK`
- a build-time assertion that the module is actually present in the base image

Base image is overridable: `docker build --build-arg NGINX_IMAGE=nginx:1.29-alpine .`

## Quick start

From the repository root:

```bash
make nginx-build      # build nginx-acme:latest
make nginx-test       # config + module + HTTP smoke tests
make nginx-run        # docker compose up -d
```

Or directly:

```bash
cd nginx
docker compose up -d --build
curl http://localhost
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
   docker exec nginx-acme nginx -s reload
   docker logs -f nginx-acme
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

`docker-compose.yml` maps it to the `nginx-acme-state` named volume. The systemd
unit bind-mounts the host's `/var/nginx-acme`.

## Paths

| Path | Purpose |
|------|---------|
| `/var/www/html` | web root of the default server |
| `/etc/nginx/conf.d` | your server blocks (`include`d last) |
| `/etc/nginx/nginx.conf` | main config, override to replace it entirely |
| `/var/nginx-acme` | **ACME state — persist this** (mode 0700, owned by `nginx`) |
| `/var/log/nginx` | logs; already symlinked to stdout/stderr |

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

## Deployment as a systemd service

See [SYSTEMD.md](SYSTEMD.md). Short version: `sudo ./install-systemd.sh` from
this directory, after `make nginx-build`.

## Debugging

```bash
docker logs nginx-acme                 # ACME errors show up here
docker exec nginx-acme nginx -t        # validate config
docker exec nginx-acme nginx -s reload # apply config changes
docker inspect -f '{{.State.Health.Status}}' nginx-acme
docker exec nginx-acme ls -la /var/nginx-acme
```

Common failures:

- **`nginx: [emerg] module ... not found`** — the base image no longer ships
  `nginx-module-acme` (it is not built for `armhf`, for instance). The build
  itself asserts this, so a successful build rules it out.
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
make nginx-test      # fast: module present, config parses, HTTP serves, healthy
make nginx-e2e       # real certificate issuance, offline, ~1 minute
```

`make nginx-test` runs `test/run-smoke.sh`: the module file exists, `nginx -t`
loads it, an `acme_certificate` server block parses, HTTP is served from a
mounted web root, and the container's health check turns green.

`make nginx-e2e` runs `test/run-e2e.sh`, which stands up
[Pebble](https://github.com/letsencrypt/pebble) — Let's Encrypt's own test ACME
server — next to this image and makes nginx actually obtain and serve a
certificate. No domain, no internet, no Let's Encrypt account involved.

It matters that the drop-in at `test/conf.d/e2e.conf` is loaded by the **real
`nginx.conf` from the image**, unmodified. So the test fails if the shipped
config, the module, or the base image drift apart — which a `nginx -t` check
cannot detect.

Add `--keep` to leave the stack up and poke at it:

```bash
nginx/test/run-e2e.sh --keep
docker compose -f nginx/test/docker-compose.e2e.yml -p nginx-acme-e2e logs -f nginx
```

## CI

`.github/workflows/build-nginx.yml` builds for `linux/amd64` and `linux/arm64`
and runs `make nginx-test` on each. A separate job runs `make nginx-e2e` on
amd64. CI only adds the build cache and the arm64 build; the checks themselves
are the Makefile's, so what passes locally is what passes in CI.
