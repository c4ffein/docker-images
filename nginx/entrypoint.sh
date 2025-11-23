#!/bin/sh
set -e

# Create necessary directories if they don't exist
mkdir -p /var/www/html
mkdir -p /var/www/acme
mkdir -p /etc/nginx/acme/certs
mkdir -p /etc/nginx/conf.d

# Set proper permissions
chown -R nginx:nginx /var/www/html /var/www/acme /etc/nginx/acme

# Create default index.html if it doesn't exist
if [ ! -f /var/www/html/index.html ]; then
    cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>nginx</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
        }
        h1 { color: #009639; }
        code {
            background: #f4f4f4;
            padding: 2px 6px;
            border-radius: 3px;
        }
    </style>
</head>
<body>
    <h1>nginx is running!</h1>
    <p>Server: <code>$(hostname)</code></p>
</body>
</html>
EOF
fi

# Test nginx configuration
echo "Testing nginx configuration..."
nginx -t

# Execute the main command
exec "$@"
