# nginx with the official ACME module (automatic Let's Encrypt certificates).
#
# The upstream nginx Alpine image ships nginx-module-acme since nginx 1.29, so
# there is nothing to compile here: we only need to fail loudly if a base image
# bump ever drops the module, and to ship our config + entrypoint.
ARG NGINX_IMAGE=nginx:mainline-alpine
FROM ${NGINX_IMAGE}
# ARGs declared before FROM are not visible in the build stage
ARG NGINX_IMAGE

LABEL org.opencontainers.image.title="nginx-acme" \
      org.opencontainers.image.description="nginx with the ngx_http_acme_module for automatic ACME/Let's Encrypt certificates" \
      org.opencontainers.image.source="https://github.com/c4ffein/docker-images" \
      org.opencontainers.image.licenses="MIT"

# Guard: the whole point of this image is the ACME module.
RUN test -f /usr/lib/nginx/modules/ngx_http_acme_module.so \
 || (echo "ngx_http_acme_module.so missing from ${NGINX_IMAGE}" >&2; exit 1)

COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh
# The base image's conf.d/default.conf declares a `localhost` server rooted at
# /usr/share/nginx/html, which would shadow our default server for that Host.
RUN rm -f /etc/nginx/conf.d/default.conf \
 && chmod +x /entrypoint.sh \
 && mkdir -p /var/www/html /var/nginx-acme \
 && chown nginx:nginx /var/nginx-acme

EXPOSE 80 443

# Liveness only: any HTTP response means the worker is up. Deliberately not
# `-f`, so a 404 from an empty web root still counts as healthy.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -sS -o /dev/null http://127.0.0.1/ || exit 1

STOPSIGNAL SIGQUIT

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
