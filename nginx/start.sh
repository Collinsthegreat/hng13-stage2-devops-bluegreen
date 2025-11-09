#!/bin/bash
set -e

# Substitute environment variables
envsubst '$PRIMARY $BACKUP $PORT $PROXY_TIMEOUT $REQUEST_TIMEOUT' \
    < /etc/nginx/nginx.conf.template \
    > /etc/nginx/nginx.conf

echo "Nginx config generated with PRIMARY=$PRIMARY BACKUP=$BACKUP PORT=$PORT"

# Start Nginx in foreground
nginx -g 'daemon off;'



