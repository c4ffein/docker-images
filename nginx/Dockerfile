# nginx that runs as a non-root user, with the official ACME module.
#
# Base: nginxinc/nginx-unprivileged, slim Alpine variant. That is nginx and
# nothing else: no njs, xslt, geoip or image-filter modules, no curl. The whole
# process tree runs as uid 101, so the container never needs setuid, setgid or
# chown capabilities.
#
# The unprivileged image does not ship nginx-module-acme, so it is installed
# here from the same signed nginx.org apk repository the base image got nginx
# from. Nothing is compiled.
ARG NGINX_IMAGE=nginxinc/nginx-unprivileged:mainline-alpine-slim
FROM ${NGINX_IMAGE}
# ARGs declared before FROM are not visible in the build stage
ARG NGINX_IMAGE

# nginx-acme release packaged with this nginx version. The apk is versioned
# <nginx>.<acme>-r<release> and depends on the exact nginx version, so this
# must match the base image. When bumping the base, take ACME_VERSION from
# https://github.com/nginx/docker-nginx/blob/master/mainline/alpine/Dockerfile
ARG ACME_VERSION=0.4.1

LABEL org.opencontainers.image.title="nginx-acme" \
      org.opencontainers.image.description="non-root nginx with the ngx_http_acme_module for automatic ACME/Let's Encrypt certificates" \
      org.opencontainers.image.source="https://github.com/c4ffein/docker-images" \
      org.opencontainers.image.licenses="MIT"

USER root
RUN set -eux; \
    repo="https://nginx.org/packages/mainline/alpine/v$(grep -Eo '^[0-9]+\.[0-9]+' /etc/alpine-release)/main"; \
    apk add -X "$repo" --no-cache "nginx-module-acme=${NGINX_VERSION}.${ACME_VERSION}-r${PKG_RELEASE}"; \
    test -f /usr/lib/nginx/modules/ngx_http_acme_module.so; \
# File capability so the non-root master can bind 80/443 under --network host,
# where Docker's in-container ip_unprivileged_port_start=0 does not apply.
# It only takes effect when the container keeps NET_BIND_SERVICE in its
# bounding set and does NOT set no-new-privileges (see nginx-docker.service).
# On a bridge network it is simply unused.
    apk add --no-cache --virtual .setcap libcap; \
    setcap cap_net_bind_service=+ep /usr/sbin/nginx; \
    apk del .setcap; \
# The base image's default server (listen 8080, /usr/share/nginx/html) would
# shadow ours for Host: localhost.
    rm -f /etc/nginx/conf.d/default.conf; \
    mkdir -p /var/www/html /var/nginx-acme; \
    chown 101:101 /var/nginx-acme; \
    chmod 700 /var/nginx-acme

COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80 443

# Liveness only. /healthz is answered by the default server in nginx.conf for
# loopback clients, so an empty web root still counts as healthy. busybox
# wget, no curl in this image.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1

# ENTRYPOINT, CMD and STOPSIGNAL (SIGQUIT) come from the base image.
USER 101

# Fail the build, not the first start, if the config and the module disagree.
RUN nginx -t
