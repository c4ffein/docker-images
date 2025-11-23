# Multi-stage build for nginx with ACME support on Alpine
FROM alpine:3.19 AS builder

# nginx version to build
ARG NGINX_VERSION=1.26.2
ARG ACME_MODULE_VERSION=master

# Install build dependencies
RUN apk add --no-cache \
    gcc \
    g++ \
    libc-dev \
    make \
    openssl-dev \
    pcre2-dev \
    zlib-dev \
    linux-headers \
    curl \
    git \
    libxml2-dev \
    libxslt-dev \
    gd-dev \
    geoip-dev \
    clang17-dev \
    clang17-static \
    clang17-libclang \
    llvm17-dev \
    llvm17-static

# Install Rust via rustup (Alpine's Rust is too old for ACME module)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

# Configure for static linking with libclang
ENV LIBCLANG_PATH=/usr/lib
ENV LIBCLANG_STATIC_PATH=/usr/lib
ENV CLANG_PATH=/usr/bin/clang
ENV RUSTFLAGS="-C target-feature=-crt-static"

# Download and verify nginx
WORKDIR /usr/src
RUN curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz && \
    tar -xzf nginx.tar.gz && \
    rm nginx.tar.gz

# Clone the nginx ACME module
RUN git clone https://github.com/nginx/nginx-acme.git

# Build nginx with ACME module
WORKDIR /usr/src/nginx-${NGINX_VERSION}
RUN ./configure \
    --prefix=/etc/nginx \
    --sbin-path=/usr/sbin/nginx \
    --modules-path=/usr/lib/nginx/modules \
    --conf-path=/etc/nginx/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-http_ssl_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_mp4_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_random_index_module \
    --with-http_secure_link_module \
    --with-http_stub_status_module \
    --with-http_auth_request_module \
    --with-http_xslt_module=dynamic \
    --with-http_image_filter_module=dynamic \
    --with-http_geoip_module=dynamic \
    --with-threads \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-stream_realip_module \
    --with-stream_geoip_module=dynamic \
    --with-http_slice_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-compat \
    --with-file-aio \
    --with-http_v2_module \
    --with-http_v3_module \
    --add-dynamic-module=/usr/src/nginx-acme \
    && make -j$(nproc) \
    && make install

# Create necessary directories
RUN mkdir -p /var/cache/nginx/client_temp \
    /var/cache/nginx/proxy_temp \
    /var/cache/nginx/fastcgi_temp \
    /var/cache/nginx/uwsgi_temp \
    /var/cache/nginx/scgi_temp

# Final stage - minimal Alpine runtime image
FROM alpine:3.19

# Install runtime dependencies
RUN apk add --no-cache \
    ca-certificates \
    openssl \
    pcre2 \
    zlib \
    libxslt \
    gd \
    geoip \
    curl \
    tzdata \
    libgcc \
    libstdc++

# Copy nginx from builder
COPY --from=builder /usr/sbin/nginx /usr/sbin/nginx
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /usr/lib/nginx/modules /usr/lib/nginx/modules
COPY --from=builder /var/cache/nginx /var/cache/nginx

# Create nginx user
RUN addgroup -g 101 -S nginx && \
    adduser -S -D -H -u 101 -h /var/cache/nginx -s /sbin/nologin -G nginx -g nginx nginx

# Create necessary directories and set permissions
RUN mkdir -p /var/log/nginx /var/www/html /etc/nginx/acme && \
    chown -R nginx:nginx /var/log/nginx /var/cache/nginx /etc/nginx/acme && \
    ln -sf /dev/stdout /var/log/nginx/access.log && \
    ln -sf /dev/stderr /var/log/nginx/error.log

# Copy configuration files
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 443

STOPSIGNAL SIGQUIT

ENTRYPOINT ["/entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
