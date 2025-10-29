HNG Stage 2: Blue/Green Deployment

This project demonstrates a Blue/Green deployment strategy using Docker and Nginx. Two application pools (Blue and Green) run simultaneously, and Nginx handles dynamic routing and failover in case of chaos or failures.  

Prerequisites

- Docker (v20+ recommended)
- Docker Compose (v2+ recommended)
- `curl` for API testing

Ensure your `.env` file is set up with the following environment variables:

```bash
BLUE_IMAGE=<your-blue-app-image>
GREEN_IMAGE=<your-green-app-image>
APP_PORT=3000
BLUE_PORT=8081
GREEN_PORT=8082
NGINX_PORT=8080
RELEASE_ID_BLUE=<your-blue-release-id>
RELEASE_ID_GREEN=<your-green-release-id>
