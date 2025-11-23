# nginx with ACME Module (Alpine-based)

A lightweight nginx Docker image based on Alpine Linux with ACME module support for automated SSL/TLS certificate management.

## Features

- Based on Alpine Linux for minimal image size
- nginx compiled from source with latest stable version
- ACME module for automated Let's Encrypt certificate management
- HTTP/2 and HTTP/3 support
- Multiple dynamic modules included
- Multi-stage build for optimized image size
- Security-focused configuration

## Building the Image

```bash
cd nginx
docker build -t nginx-acme:latest .
```

### Build Arguments

You can customize the build with the following arguments:

```bash
docker build \
  --build-arg NGINX_VERSION=1.26.2 \
  --build-arg ACME_MODULE_VERSION=master \
  -t nginx-acme:latest .
```

## Running the Container

### Basic Usage

```bash
docker run -d \
  --name nginx-acme \
  -p 80:80 \
  -p 443:443 \
  nginx-acme:latest
```

### With Custom Configuration

```bash
docker run -d \
  --name nginx-acme \
  -p 80:80 \
  -p 443:443 \
  -v $(pwd)/custom-nginx.conf:/etc/nginx/nginx.conf:ro \
  -v $(pwd)/html:/var/www/html \
  -v nginx-acme-certs:/etc/nginx/acme \
  nginx-acme:latest
```

### With Docker Compose

Create a `docker-compose.yml`:

```yaml
version: '3.8'

services:
  nginx:
    build: ./nginx
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./html:/var/www/html
      - ./conf.d:/etc/nginx/conf.d:ro
      - nginx-certs:/etc/nginx/acme
    restart: unless-stopped

volumes:
  nginx-certs:
```

Run with:

```bash
docker-compose up -d
```

## ACME Module Configuration

The ACME module is loaded dynamically and configured in `nginx.conf`. Here's how to use it:

### Directory Structure

```
/etc/nginx/acme/
├── account.key          # ACME account key
└── certs/              # Directory for certificates
    └── example.com/
        ├── fullchain.pem
        └── privkey.pem
```

### Requesting Certificates

The ACME module handles certificate requests automatically. Configure your server block:

```nginx
server {
    listen 80;
    server_name example.com;

    location /.well-known/acme-challenge/ {
        default_type "text/plain";
        root /var/www/acme;
    }

    # Redirect to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name example.com;

    ssl_certificate /etc/nginx/acme/certs/example.com/fullchain.pem;
    ssl_certificate_key /etc/nginx/acme/certs/example.com/privkey.pem;

    # Your application configuration
    location / {
        root /var/www/html;
        index index.html;
    }
}
```

## Volumes

| Path | Description |
|------|-------------|
| `/var/www/html` | Web root directory |
| `/etc/nginx/acme` | ACME certificates and keys |
| `/etc/nginx/conf.d` | Additional nginx configurations |
| `/var/log/nginx` | nginx logs (stdout/stderr by default) |

## Environment Variables

Currently, the image doesn't use environment variables for configuration. All configuration is done through nginx config files.

## Included Modules

### Static Modules
- http_ssl_module
- http_v2_module
- http_v3_module
- http_realip_module
- http_addition_module
- http_sub_module
- http_dav_module
- http_flv_module
- http_mp4_module
- http_gunzip_module
- http_gzip_static_module
- http_random_index_module
- http_secure_link_module
- http_stub_status_module
- http_auth_request_module
- stream_ssl_module
- stream_realip_module
- And more...

### Dynamic Modules
- http_xslt_module
- http_image_filter_module
- http_geoip_module
- stream_geoip_module
- **ngx_http_acme_module**

## Security Considerations

1. **Certificate Storage**: Always use Docker volumes for `/etc/nginx/acme` to persist certificates
2. **Key Permissions**: The entrypoint script sets proper permissions for certificate directories
3. **Updates**: Regularly rebuild the image to get the latest nginx and security patches
4. **Configuration**: Review and customize `nginx.conf` for your security requirements

## Debugging

### View logs
```bash
docker logs nginx-acme
```

### Execute commands in running container
```bash
docker exec -it nginx-acme sh
```

### Test nginx configuration
```bash
docker exec nginx-acme nginx -t
```

### Reload nginx configuration
```bash
docker exec nginx-acme nginx -s reload
```

## Common Issues

### ACME Module Not Loading

Check if the module is loaded:
```bash
docker exec nginx-acme nginx -V
```

Look for `--add-dynamic-module=/usr/src/nginx-acme` in the output.

### Certificate Permissions

Ensure the nginx user has read access to certificates:
```bash
docker exec nginx-acme ls -la /etc/nginx/acme/certs/
```

## Publishing to Docker Hub

1. **Tag the image**:
   ```bash
   docker tag nginx-acme:latest yourusername/nginx-acme:latest
   docker tag nginx-acme:latest yourusername/nginx-acme:1.26.2
   ```

2. **Push to Docker Hub**:
   ```bash
   docker push yourusername/nginx-acme:latest
   docker push yourusername/nginx-acme:1.26.2
   ```

## CI/CD Pipeline

See the root repository for GitHub Actions workflow examples that automatically build and push this image to Docker Hub.
