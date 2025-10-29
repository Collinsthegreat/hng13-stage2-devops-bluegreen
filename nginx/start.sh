#!/bin/bash
set -e

# Substitute environment variables into the nginx config
envsubst '$PRIMARY $BACKUP $APP_PORT $PROXY_TIMEOUT $REQUEST_TIMEOUT' \
    < /etc/nginx/nginx.conf.template \
    > /etc/nginx/nginx.conf

echo "Nginx config generated with PRIMARY=$PRIMARY BACKUP=$BACKUP APP_PORT=$APP_PORT"

# Start nginx
nginx -g 'daemon off;'
