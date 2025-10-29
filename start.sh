# --- start.sh ---
#!/bin/bash
set -euo pipefail

# Load env (if exists)
if [ -f .env ]; then
  # shellcheck disable=SC1091
  export $(grep -v '^#' .env | xargs) || true
fi

: "${ACTIVE_POOL:=blue}"
: "${APP_PORT:=5000}"
: "${PROXY_TIMEOUT:=2}"
: "${REQUEST_TIMEOUT:=2}"
: "${BLUE_PORT:=8081}"
: "${GREEN_PORT:=8082}"
: "${NGINX_PORT:=8080}"

# Choose primary/backup based on ACTIVE_POOL
if [ "$ACTIVE_POOL" = "blue" ]; then
  export PRIMARY="app_blue"
  export BACKUP="app_green"
else
  export PRIMARY="app_green"
  export BACKUP="app_blue"
fi

# Ensure nginx dir exists
mkdir -p nginx

# Render template -> nginx/nginx.conf
envsubst '\$PRIMARY \$BACKUP \$APP_PORT \$PROXY_TIMEOUT \$REQUEST_TIMEOUT' < nginx/nginx.conf.template > nginx/nginx.conf

echo "Generated nginx/nginx.conf with PRIMARY=$PRIMARY BACKUP=$BACKUP (app port $APP_PORT)"

# Start (or recreate) stack
docker compose down --remove-orphans || true
docker compose pull
docker compose up -d

echo "Stack started. Nginx: http://localhost:${NGINX_PORT}"
