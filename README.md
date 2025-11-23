# Docker Images Collection

A collection of custom Docker images optimized for my needs

## Quick Start

The easiest way to work with these images is using the Makefile - see `make help`

## Available Images

### nginx with ACME Module
A lightweight nginx image with built-in ACME module support for automated SSL/TLS certificate management, on top of Alpine.

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
