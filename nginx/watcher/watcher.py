#!/usr/bin/env python3
import os
import re
import time
import requests
from collections import deque
from datetime import datetime

LOG_PATH = os.environ.get("NGINX_LOG_PATH", "/var/log/nginx/access.log")
WEBHOOK = os.environ.get("SLACK_WEBHOOK_URL", "").strip()
WINDOW_SIZE = int(os.environ.get("WINDOW_SIZE", "200"))
ERROR_RATE_THRESHOLD = float(os.environ.get("ERROR_RATE_THRESHOLD", "2.0"))
ALERT_COOLDOWN_SEC = int(os.environ.get("ALERT_COOLDOWN_SEC", "300"))
MAINTENANCE = os.environ.get("MAINTENANCE_MODE", "false").lower() in ("1", "true", "yes")

RE = re.compile(
    r'HTTP/\d\.\d"\s+(\d{3}).*pool=(\w+)\s+release=([^\s]+)\s+upstream_status=([^\s]+)\s+upstream_addr=([^\s]+)'
)

history = deque(maxlen=WINDOW_SIZE)
last_pool = None
last_alert_time = {}


def post_slack(text, title="Alert"):
    if not WEBHOOK:
        print("⚠️ SLACK_WEBHOOK_URL not set; would post:", title, text)
        return
    payload = {"text": f"*{title}*\n{text}"}
    try:
        r = requests.post(WEBHOOK, json=payload, timeout=5)
        print(f"✅ Slack POST {r.status_code}")
    except Exception as e:
        print("❌ Failed to send Slack:", e)


def wait_for_file(path):
    print(f"⏳ Waiting for log file {path} ...")
    while not os.path.exists(path):
        time.sleep(1)
    print(f"✅ Found log file: {path}")


def tail_file(path):
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        f.seek(0, 2)
        while True:
            line = f.readline()
            if line:
                yield line.strip()
            else:
                time.sleep(0.2)


def main():
    global last_pool
    wait_for_file(LOG_PATH)
    print("👀 Starting to watch log file...")

    for line in tail_file(LOG_PATH):
        print("📜 DEBUG:", line)
        m = RE.search(line)
        if not m:
            continue

        status, pool, release, upstream_status, upstream_addr = m.groups()
        code = int(status)
        is_5xx = 500 <= code < 600
        history.append(is_5xx)

        # Failover detection
        if last_pool is None:
            last_pool = pool
        elif pool != last_pool:
            now = datetime.utcnow()
            la = last_alert_time.get("failover")
            if not MAINTENANCE and (la is None or (now - la).total_seconds() > ALERT_COOLDOWN_SEC):
                text = (
                    f"Failover detected: {last_pool} → {pool}\n"
                    f"Upstream: {upstream_addr}\n"
                    f"Release: {release}\n"
                    f"Time: {now.isoformat()} UTC\n"
                    f"Log line: {line}"
                )
                post_slack(text, title="Failover detected")
                last_alert_time["failover"] = now
            last_pool = pool

        # Error rate alert
        if len(history) == WINDOW_SIZE:
            error_count = sum(history)
            pct = (error_count / WINDOW_SIZE) * 100.0
            now = datetime.utcnow()
            la = last_alert_time.get("rate")
            if pct >= ERROR_RATE_THRESHOLD and not MAINTENANCE:
                if la is None or (now - la).total_seconds() > ALERT_COOLDOWN_SEC:
                    text = (
                        f"High 5xx rate: {pct:.2f}% over last {WINDOW_SIZE} requests\n"
                        f"Error count: {error_count}/{WINDOW_SIZE}\n"
                        f"Time: {now.isoformat()} UTC"
                    )
                    post_slack(text, title="High error rate")
                    last_alert_time["rate"] = now


if __name__ == "__main__":
    main()
