🧭 Runbook — Blue/Green Observability
Overview

This Hybrid Nginx Log Watcher continuously monitors nginx/logs/access.log for:

🔄 Failover events

✅ Recovery events

🚨 High 5xx error rates

All alerts are sent to Slack via a configured webhook for immediate visibility and operational response.

🔄 Failover Detected

Meaning:
Nginx has switched traffic from one upstream pool to another (e.g., blue → green).
This usually indicates that the previous pool has become unhealthy or that a redeployment triggered an intentional switch.

Slack Example:

Failover detected: blue → green
Upstream: 127.0.0.1
Release: green-v1
Time: 2025-10-31T14:20:15Z

Operator Steps:

Check the running containers:

docker ps


Review logs for the previous pool (e.g., blue):

docker logs app_blue | tail -n 50


Test its health endpoint:

curl -i http://localhost:8081/healthz


If the pool is unhealthy, restart or rebuild it.

To forcefully switch pools (if needed):

Edit .env:

ACTIVE_POOL=<new_pool>


Restart the stack:

./start.sh

✅ Recovery Detected

Meaning:
Traffic has switched back to the previously failed pool (e.g., green → blue), confirming that it has recovered and is now stable.

Slack Example:

Recovery detected: traffic switched back to blue
Upstream: 127.0.0.1
✅ Service restored to primary pool.

Operator Steps:

Confirm both pools are running correctly:

docker ps
curl -i http://localhost:8081/healthz
curl -i http://localhost:8082/healthz


Check the Slack timestamp to verify recovery timing.

Ensure no 5xx errors persist.

Mark the incident as resolved in your monitoring dashboard.

🚨 High 5xx Error Rate

Meaning:
More than ERROR_RATE_THRESHOLD% of requests in the last WINDOW_SIZE contained 5xx responses, indicating instability or backend failure.

Slack Example:

High 5xx Error Rate: 100.00% over last 100 requests
Error Count: 100
Threshold: 2.0%

Operator Steps:

Review recent Nginx access logs:

docker exec -it nginx sh -c "tail -n 200 /var/log/nginx/access.log"


Identify which pool is producing 5xx responses.

Inspect that pool’s logs:

docker logs app_green | tail -n 50


Check health endpoints:

curl -i http://localhost:8081/healthz


If errors persist, consider a rollback or redeploy of the affected pool.

⚙️ Suppression / Maintenance Mode

Purpose:
Use during deployments or planned maintenance to temporarily disable Slack alerts.

How to Enable:

export MAINTENANCE_MODE=true


Or edit .env:

MAINTENANCE_MODE=true


Then restart the watcher (or its container):

docker restart watcher

🔐 Configuration Reference
Variable	Description	Default
SLACK_WEBHOOK_URL	Slack Incoming Webhook URL (keep secret)	—
WINDOW_SIZE	Number of recent requests tracked	200
ERROR_RATE_THRESHOLD	% threshold for 5xx alerts	2.0
ALERT_COOLDOWN_SEC	Minimum seconds between duplicate alerts	300
MAINTENANCE_MODE	Suppress alerts during deployments	false

Logs Monitored:

nginx/logs/access.log

🧪 Testing Alerts

You can simulate watcher behavior manually for validation.

1. Failover Simulation
echo '{"pool":"green","release":"green-v1","status":200,"upstream_status":"200","upstream_addr":"127.0.0.1"}' >> nginx/logs/access.log

2. Recovery Simulation
echo '{"pool":"blue","release":"blue-v1","status":200,"upstream_status":"200","upstream_addr":"127.0.0.1"}' >> nginx/logs/access.log

3. High Error Rate Simulation
for i in {1..50}; do
  echo '{"pool":"green","release":"green-v1","status":502,"upstream_status":"502","upstream_addr":"127.0.0.1"}' >> nginx/logs/access.log
done


Verify that all corresponding alerts appear in Slack with accurate timestamps and pool transitions.

🧩 Notes

Slack webhook URLs must never be committed to version control.

The watcher supports both JSON-formatted and standard text-based Nginx logs.

Always enable maintenance mode before rolling updates or restarts.

Once recovery is detected, the system automatically resumes normal alerting.