# --- nginx/Dockerfile ---
FROM nginx:stable

# Install envsubst for variable substitution
RUN apt-get update && apt-get install -y gettext-base && rm -rf /var/lib/apt/lists/*

# Copy template and startup script
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY start.sh /start.sh

# Make it executable
RUN chmod +x /start.sh

# Environment variables that will be replaced dynamically
ENV PRIMARY=app_blue \
    BACKUP=app_green \
    APP_PORT=3000 \
    PROXY_TIMEOUT=3 \
    REQUEST_TIMEOUT=10

CMD ["/bin/bash", "/start.sh"]
