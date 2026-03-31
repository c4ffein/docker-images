# Docker Images Collection

A collection of custom Docker images optimized for my needs

## Quick Start

The easiest way to work with these images is using the Makefile - see `make help`

## Available Images

### nginx with ACME Module
A lightweight nginx image with built-in ACME module support for automated SSL/TLS certificate management, on top of Alpine.

See [nginx/README.md](nginx/README.md) for details.

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

## CI/CD

This repository uses GitHub Actions to automatically build and test images.

## License

This repository is licensed under the MIT License. See [LICENSE](./LICENSE) for details.
