# Docker Images Collection

A collection of custom Docker images optimized for production use, built on Alpine Linux for minimal size and maximum security.

## Available Images

### nginx with ACME Module
A lightweight nginx image with built-in ACME module support for automated SSL/TLS certificate management, on top of Alpine.

**Quick Start**:
```bash
cd nginx
docker build -t nginx-acme:latest .
docker run -d -p 80:80 -p 443:443 nginx-acme:latest
```

## Building Images

Each image directory contains its own Dockerfile and documentation. To build an image:

```bash
cd <image-directory>
docker build -t <image-name>:<tag> .
```

## CI/CD

This repository uses GitHub Actions to automatically build and push images to Docker Hub when changes are pushed to the main branch or when tags are created.

### Automated Builds

- **On push to main**: Builds and pushes with `latest` tag
- **On tag creation**: Builds and pushes with version tag (e.g., `v1.0.0`)

### Prerequisites for CI/CD

Set up the following secrets in your GitHub repository:

- `DOCKERHUB_USERNAME`: Your Docker Hub username
- `DOCKERHUB_TOKEN`: Your Docker Hub access token

## License

This repository is licensed under the MIT License. See [LICENSE](./LICENSE) for details.

Individual images may use components with different licenses. Check each image's README for specific license information.

## Support

For issues, questions, or suggestions:

- Open an issue on GitHub
- Check individual image READMEs for specific documentation
- Review the Dockerfile comments for implementation details
