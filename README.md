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

Running the Stack

Clean up the environment (remove existing containers, networks, volumes):

docker compose down --volumes --remove-orphans


Start the stack:

./start.sh


This script will:

Dynamically generate nginx/nginx.conf with the correct primary (active) and backup pool.

Start the Blue and Green app containers along with Nginx.

Expose the services on the ports defined in .env.

Verify that all containers are running:

docker ps


You should see app_blue, app_green, and nginx running and healthy.

Testing the Deployment

Check baseline application version through Nginx:

curl -i http://localhost:8080/version


X-App-Pool header shows the currently active pool (Blue or Green).

X-Release-Id shows the release identifier for the active pool.

Trigger chaos on the active pool:

 If Blue is active
curl -X POST http://localhost:8081/chaos/start?mode=error

 If Green is active
curl -X POST http://localhost:8082/chaos/start?mode=error


This simulates an error in the active pool and forces failover.

Verify failover:

./verify_failover.sh


Checks responses for 10 seconds to confirm that at least 95% of traffic is served by the backup pool.

Ensures all HTTP responses are 200 OK.

Restores the original pool after verification.

Stop chaos simulation:

 Stop chaos for Blue
curl -X POST http://localhost:8081/chaos/stop

 Stop chaos for Green
curl -X POST http://localhost:8082/chaos/stop


Confirm original application version is restored:

curl -i http://localhost:8080/version

Project Features

Blue/Green deployment: Active and backup application pools with seamless failover.

Automated health checks: Nginx monitors container health and reroutes traffic.

Chaos simulation: Test failover behavior using /chaos/start and /chaos/stop endpoints.

Dynamic configuration: Nginx configuration is generated from environment variables.
