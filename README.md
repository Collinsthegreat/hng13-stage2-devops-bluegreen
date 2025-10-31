HNG Stage 2: Blue/Green Deployment

This project demonstrates a Blue/Green deployment strategy using Docker and Nginx. Two application pools (Blue and Green) run simultaneously, and Nginx handles dynamic routing and failover in case of chaos or failures.

Prerequisites

Docker (v20+ recommended)

Docker Compose (v2+ recommended)

curl for API testing

Ensure your .env file is set up with the following environment variables:

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

If Blue is active:

curl -X POST http://localhost:8081/chaos/start?mode=error


If Green is active:

curl -X POST http://localhost:8082/chaos/start?mode=error


This simulates an error in the active pool and forces failover.

Verify failover:

./verify_failover.sh


Checks responses for 10 seconds to confirm that at least 95% of traffic is served by the backup pool.
Ensures all HTTP responses are 200 OK.
Restores the original pool after verification.

Stop chaos simulation:

Stop chaos for Blue:

curl -X POST http://localhost:8081/chaos/stop


Stop chaos for Green:

curl -X POST http://localhost:8082/chaos/stop


Confirm original application version is restored:

curl -i http://localhost:8080/version

Project Features

Blue/Green deployment: Active and backup application pools with seamless failover.

Automated health checks: Nginx monitors container health and reroutes traffic.

Chaos simulation: Test failover behavior using /chaos/start and /chaos/stop endpoints.

Dynamic configuration: Nginx configuration is generated from environment variables.

🚀 HNG Stage 3: Observability & Alerts (Log-Watcher + Slack Integration)

This stage extends the Blue/Green deployment by adding real-time observability and automated Slack alerts.
A lightweight Python service continuously monitors Nginx access logs for failover events, upstream errors, and recovery states, providing DevOps visibility into production behavior.

🔍 Overview

Goal: Detect and alert on:

Failover events (Blue → Green or Green → Blue)

Elevated 5xx error rates over a rolling window

Recovery when the primary pool returns healthy

All alerts are sent to Slack through a configurable Incoming Webhook.

⚙️ Environment Variables (.env)

Add the following new variables in addition to your Stage 2 ones:

SLACK_WEBHOOK_URL=https://hooks.slack.com/services/xxxxx/yyyyy/zzzzz
ACTIVE_POOL=blue
ERROR_RATE_THRESHOLD=2
WINDOW_SIZE=200
ALERT_COOLDOWN_SEC=300
MAINTENANCE_MODE=false


Descriptions:

SLACK_WEBHOOK_URL – your Slack incoming webhook URL

ACTIVE_POOL – initial active pool (blue or green)

ERROR_RATE_THRESHOLD – error percentage to trigger alert

WINDOW_SIZE – number of requests to evaluate

ALERT_COOLDOWN_SEC – cooldown before repeating alerts

MAINTENANCE_MODE – optional flag to suppress alerts during planned toggles

🧩 Components
1. Nginx

Logs pool, release ID, upstream status, and latency.

Example log format:

$remote_addr - $remote_user [$time_local] "$request" $status $body_bytes_sent
pool=$http_x_app_pool release=$http_x_release_id
upstream_status=$upstream_status upstream=$upstream_addr
request_time=$request_time upstream_time=$upstream_response_time


Logs are stored in /var/log/nginx/access.log and shared with the watcher.

2. Watcher (Python Service)

Continuously tails the Nginx log file.

Detects:

Failover changes (Blue ↔ Green)

High error rates (e.g., 5xx > 2%)

Recovery of the original pool

Sends alerts to Slack with cooldown and deduplication logic.

3. Slack Alerts

Alerts are human-readable and color-coded:

⚠️ Failover Detected — Blue → Green or Green → Blue

🚨 High Error Rate — 5xx errors exceed threshold

✅ Recovery Detected — Primary pool restored

🧪 Running and Testing
1. Start Services
docker compose up -d --build


Verify running containers:

docker ps


Expected: app_blue, app_green, nginx, alert_watcher.

2. Baseline Test
curl -i http://localhost:8080/version


Check X-App-Pool and X-Release-Id headers.

3. Chaos and Failover Test

If Blue is active:

curl -X POST http://localhost:8081/chaos/start?mode=error


If Green is active:

curl -X POST http://localhost:8082/chaos/start?mode=error


Expected Slack alert:

⚠️ Failover Detected — Traffic switched from Blue → Green

4. Recovery Test

Stop chaos on failed pool:

curl -X POST http://localhost:8081/chaos/stop   # or 8082


Expected Slack alert:

✅ Recovery Detected — Blue is now serving traffic again

5. Error-Rate Simulation

Simulate 5xx errors to breach threshold; watcher triggers alert:

🚨 High Error Rate — 5xx > 2% over last 200 requests

📸 Verification Screenshots (Required)
Screenshot	Description
1️⃣	Slack Alert – Failover Event
2️⃣	Slack Alert – High Error Rate
3️⃣	Nginx Log Snippet showing structured fields
📚 Runbook Summary
Alert	Meaning	Operator Action
⚠️ Failover Detected	Active pool failed; backup took over	Check health of primary container
🚨 High Error Rate	Error-rate threshold exceeded	Inspect upstream logs, confirm root cause
✅ Recovery Detected	Primary pool recovered	Monitor stability before removing maintenance mode
🧰 Suppressing Alerts During Maintenance

If performing planned deploys:

MAINTENANCE_MODE=true


Then restart the watcher container. Alerts are suppressed until set back to false.

📁 Repository Structure
.
├── docker-compose.yml
├── nginx/
│   └── nginx.conf.template
├── watcher/
│   ├── watcher.py
│   ├── requirements.txt
├── runbook.md
├── README.md
├── .env.example
└── screenshots/
    ├── failover_alert.png
    ├── error_rate_alert.png
    └── nginx_log.png

✅ Acceptance Criteria Checklist

 Custom Nginx log format with pool/release/upstream info

 Shared volume for logs between Nginx and watcher

 Slack alerts for failover, recovery, and error-rate breach

 Cooldown to prevent spam

 Environment-variable-driven configuration

 Clear operator runbook

 Stage 2 baseline and chaos tests still functional

🏁 Conclusion

This project now delivers a complete Blue/Green deployment pipeline enhanced with observability, alerting, and operational insight.
It simulates real-world production readiness by ensuring failures, recoveries, and performance degradations are instantly visible in Slack.
