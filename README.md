# Docker Images Collection

A collection of custom Docker images optimized for my needs

## Quick Start

The easiest way to work with these images is using the Makefile - see `make help`

## Available Images

### nginx with ACME Module
Non-root nginx on Alpine that obtains and renews Let's Encrypt certificates by
itself, through the official [nginx-acme](https://github.com/nginx/nginx-acme)
module - no certbot, no cron. Built on the upstream
`nginxinc/nginx-unprivileged` slim image plus the signed `nginx-module-acme`
package from nginx.org, so nothing is compiled here. Runs with a read-only root
filesystem and no capabilities; plain `docker run`, no compose.

See [nginx/README.md](nginx/README.md) for details, and
[nginx/SYSTEMD.md](nginx/SYSTEMD.md) to run it as a systemd service.

### Dev Environment
My own reusable dev environment as a docker image:

- **Python** via [uv](https://github.com/astral-sh/uv) (3.14 default)
- **Bun** (latest)
- **Claude Code** (standalone binary)
- **Neovim** with [c4ffein-configs](https://github.com/c4ffein/c4ffein-configs)
- **Build tools** - git, curl, gcc/g++/make (build-essential)
- **Shell** - bash with aliases (`la`, `gr`, `p`) and git shortcuts (`st`, `co`, `br`, `lol`, ...)
- **24-bit color** support out of the box

## Building Images Manually

Each image directory contains its own Dockerfile and documentation:

```bash
cd <image-directory>
docker build -t <image-name>:<tag> .
```

`make check` reports the local Docker setup and which of these images are
already built.

## CI/CD

This repository uses GitHub Actions to automatically build and test images.

## License

This repository is licensed under the MIT License. See [LICENSE](./LICENSE) for details.
