# --- start.sh ---
#!/bin/bash
set -eu  # Removed pipefail for Railway compatibility

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
  PRIMARY="app_blue"
  BACKUP="app_green"
else
  PRIMARY="app_green"
  BACKUP="app_blue"
fi

# Ensure nginx dir exists
mkdir -p nginx

# Render template -> nginx/nginx.conf using sed
sed -e "s|\$PRIMARY|$PRIMARY|g" \
    -e "s|\$BACKUP|$BACKUP|g" \
    -e "s|\$APP_PORT|$APP_PORT|g" \
    -e "s|\$PROXY_TIMEOUT|$PROXY_TIMEOUT|g" \
    -e "s|\$REQUEST_TIMEOUT|$REQUEST_TIMEOUT|g" \
    nginx/nginx.conf.template > nginx/nginx.conf

echo "Generated nginx/nginx.conf with PRIMARY=$PRIMARY BACKUP=$BACKUP (app port $APP_PORT)"

# Start (or recreate) stack
docker compose down --remove-orphans || true
docker compose pull
docker compose up -d

echo "Stack started. Nginx: http://localhost:${NGINX_PORT}"
