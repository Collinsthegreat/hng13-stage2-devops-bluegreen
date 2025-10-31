#!/usr/bin/env python3
"""
Hybrid Nginx Log Watcher with Slack Alerting + Recovery Detection
-----------------------------------------------------------------
Combines simplicity, visibility, and structured Slack formatting.
Now includes detection for recovery events (failover → back to primary).
"""

import os
import re
import time
import json
import sys
from collections import deque
from datetime import datetime
from typing import Optional, Dict
import requests

# ==============================
#  Configuration
# ==============================
LOG_FILE_PATH = os.getenv("NGINX_LOG_PATH", "nginx/logs/access.log")
print(f"[DEBUG] Using log file path: {LOG_FILE_PATH}")
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL", "")
WINDOW_SIZE = int(os.getenv("WINDOW_SIZE", "200"))
ERROR_RATE_THRESHOLD = float(os.getenv("ERROR_RATE_THRESHOLD", "2.0"))
ALERT_COOLDOWN_SEC = int(os.getenv("ALERT_COOLDOWN_SEC", "300"))
MAINTENANCE_MODE = os.getenv("MAINTENANCE_MODE", "false").lower() in ("1", "true", "yes")

# ==============================
#  State Tracking
# ==============================
last_pool = None
primary_pool = None
request_window = deque(maxlen=WINDOW_SIZE)
last_alert_times = {"failover": 0, "error_rate": 0, "recovery": 0}
in_failover = False  # tracks whether currently in failover state

# ==============================
#  Slack Alert Function
# ==============================
def send_slack_alert(message: str, alert_type: str, metadata: Optional[Dict] = None) -> None:
    """Send alert message to Slack using modern formatting."""
    if not SLACK_WEBHOOK_URL:
        print(f"[WARN] No SLACK_WEBHOOK_URL configured. Message: {message}")
        return

    if MAINTENANCE_MODE:
        print(f"[INFO] Maintenance mode ON. Skipping alert: {message}")
        return

    emoji_map = {
        "failover": ":arrows_counterclockwise:",
        "error_rate": ":rotating_light:",
        "recovery": ":white_check_mark:",
        "info": ":information_source:"
    }
    emoji = emoji_map.get(alert_type, ":warning:")

    payload = {
        "text": f"{emoji} *{alert_type.upper().replace('_', ' ')}*",
        "blocks": [
            {"type": "header", "text": {"type": "plain_text", "text": f"{emoji} {alert_type.upper().replace('_', ' ')}"}},
            {"type": "section", "text": {"type": "mrkdwn", "text": message}},
            {"type": "context", "elements": [{"type": "mrkdwn", "text": f":alarm_clock: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}"}]}
        ]
    }

    if metadata:
        fields = [{"type": "mrkdwn", "text": f"*{k}:*\n{v}"} for k, v in metadata.items()]
        payload["blocks"].insert(2, {"type": "section", "fields": fields})

    try:
        response = requests.post(SLACK_WEBHOOK_URL, json=payload, timeout=5, verify=False)
        if response.status_code == 200:
            print(f"[SLACK] {alert_type} alert sent successfully.")
        else:
            print(f"[SLACK] Failed ({response.status_code}): {response.text}")
    except Exception as e:
        print(f"[ERROR] Could not send Slack alert: {e}")


# ==============================
#  Log Parsing
# ==============================
def parse_log_line(line: str) -> Optional[Dict]:
    """Parse structured or semi-structured Nginx log line."""
    try:
        if line.strip().startswith("{"):
            data = json.loads(line)
            return {
                "pool": data.get("pool"),
                "release": data.get("release"),
                "status": int(data.get("status", 0)),
                "upstream_status": data.get("upstream_status"),
                "upstream_addr": data.get("upstream_addr"),
                "timestamp": datetime.utcnow()
            }
        else:
            pool = re.search(r'pool=(\w+)', line)
            release = re.search(r'release=([\w\.\-]+)', line)
            status = re.search(r'"[A-Z]+\s+[^\s]+\s+HTTP/[\d\.]+"\s+(\d+)', line)
            upstream_status = re.search(r'upstream_status=(\d+)', line)
            upstream_addr = re.search(r'upstream_addr=([\d\.:]+)', line)
            return {
                "pool": pool.group(1) if pool else None,
                "release": release.group(1) if release else None,
                "status": int(status.group(1)) if status else None,
                "upstream_status": upstream_status.group(1) if upstream_status else None,
                "upstream_addr": upstream_addr.group(1) if upstream_addr else None,
                "timestamp": datetime.utcnow()
            }
    except Exception as e:
        print(f"[WARN] Failed to parse line: {e}")
        return None


# ==============================
#  Detection Logic
# ==============================
def check_failover(current_pool: str, upstream_addr: str):
    """Detect pool switch (failover) and send alert."""
    global last_pool, primary_pool, in_failover
    now = time.time()

    if last_pool is None:
        last_pool = current_pool
        primary_pool = current_pool  # First detected pool becomes primary
        print(f"[INIT] Primary pool set to: {primary_pool}")
        return

    if current_pool != last_pool:
        # Failover triggered
        if now - last_alert_times["failover"] >= ALERT_COOLDOWN_SEC:
            msg = f"*Failover detected:* `{last_pool}` → `{current_pool}`\nUpstream: `{upstream_addr}`"
            send_slack_alert(msg, "failover", {"Previous Pool": last_pool, "Current Pool": current_pool})
            last_alert_times["failover"] = now
            in_failover = True
        last_pool = current_pool


def check_recovery(current_pool: str, upstream_addr: str):
    """Detect when traffic returns to the original primary pool."""
    global primary_pool, in_failover
    now = time.time()

    if in_failover and current_pool == primary_pool:
        if now - last_alert_times["recovery"] >= ALERT_COOLDOWN_SEC:
            msg = f"*Recovery detected:* traffic switched back to `{primary_pool}`\nUpstream: `{upstream_addr}`\n✅ Service restored to primary pool."
            send_slack_alert(msg, "recovery", {"Recovered Pool": current_pool, "Status": "Healthy"})
            last_alert_times["recovery"] = now
            in_failover = False
            print(f"[INFO] Recovery detected: back to {primary_pool}")


def check_error_rate():
    """Compute rolling 5xx error rate."""
    now = time.time()
    if len(request_window) < WINDOW_SIZE / 2:
        return

    errors = sum(1 for r in request_window if r["status"] >= 500)
    rate = (errors / len(request_window)) * 100

    if rate >= ERROR_RATE_THRESHOLD and now - last_alert_times["error_rate"] >= ALERT_COOLDOWN_SEC:
        send_slack_alert(
            f"*High 5xx Error Rate:* {rate:.2f}% over last {len(request_window)} requests",
            "error_rate",
            {"Error Count": errors, "Window Size": len(request_window), "Threshold": f"{ERROR_RATE_THRESHOLD}%"}
        )
        last_alert_times["error_rate"] = now


# ==============================
#  Core Watcher Loop
# ==============================
def tail_log():
    print(f" Watching log file: {LOG_FILE_PATH}")
    print(f" Config: threshold={ERROR_RATE_THRESHOLD}% window={WINDOW_SIZE} cooldown={ALERT_COOLDOWN_SEC}s")
    print(f" Slack: {'configured' if SLACK_WEBHOOK_URL else 'missing'}")
    print(" Starting to monitor logs...\n")

    while not os.path.exists(LOG_FILE_PATH):
        print(f"⏳ Waiting for {LOG_FILE_PATH} ...")
        time.sleep(2)

    with open(LOG_FILE_PATH, "r", encoding="utf-8", errors="ignore") as f:
        f.seek(0, 2)
        while True:
            line = f.readline()
            if not line:
                time.sleep(0.2)
                continue

            print("DEBUG:", line.strip())
            parsed = parse_log_line(line)
            if not parsed or not parsed.get("pool"):
                continue

            request_window.append(parsed)
            current_pool = parsed["pool"]
            upstream = parsed.get("upstream_addr")

            check_failover(current_pool, upstream)
            check_recovery(current_pool, upstream)
            check_error_rate()


# ==============================
#  Entry Point
# ==============================
if __name__ == "__main__":
    try:
        tail_log()
    except KeyboardInterrupt:
        print("\n Exiting watcher...")
        sys.exit(0)
    except Exception as e:
        print(f"[FATAL] {e}")
        sys.exit(1)
