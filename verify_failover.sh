#!/bin/bash

set -euo pipefail

# Basic settings (can be overridden via .env)
: "${NGINX_PORT:=8080}"
: "${BLUE_PORT:=8081}"
: "${GREEN_PORT:=8082}"
: "${CHECK_DURATION:=10}"    # seconds to run active checks
: "${ITER_INTERVAL:=0.25}"   # seconds between checks

BASE_URL="http://localhost:${NGINX_PORT}"
BLUE_CHAOS="http://localhost:${BLUE_PORT}/chaos/start?mode=error"
BLUE_CHAOS_STOP="http://localhost:${BLUE_PORT}/chaos/stop"
GREEN_CHAOS_STOP="http://localhost:${GREEN_PORT}/chaos/stop"   # <<< NEW

# --- NEW: Reset any prior chaos on both Blue and Green ---
curl -s -X POST "$BLUE_CHAOS_STOP" >/dev/null || true   # <<< NEW
curl -s -X POST "$GREEN_CHAOS_STOP" >/dev/null || true  # <<< NEW
sleep 1  # <<< NEW: give Nginx a moment to stabilize

echo "1) Baseline check BEFORE triggering chaos: expect X-App-Pool: blue"
resp_headers=$(curl -sI "${BASE_URL}/version")
echo "$resp_headers"
grep -qi "X-App-Pool: blue" <<<"$resp_headers" || { echo "Baseline not blue — abort"; exit 2; }

echo "2) Trigger chaos on BLUE (POST $BLUE_CHAOS)"
curl -s -X POST "$BLUE_CHAOS" >/dev/null || { echo "Failed to POST /chaos/start"; exit 3; }

echo "3) Wait briefly to allow Nginx failover"
sleep 1  # short delay so Nginx can mark Blue down

echo "4) Checking responses for ${CHECK_DURATION}s..."
end=$((SECONDS + CHECK_DURATION))
total=0
green_count=0
bad=0

while [ $SECONDS -lt $end ]; do
  total=$((total + 1))
  # capture http code and X-App-Pool header
  out=$(curl -s -i --max-time 5 "${BASE_URL}/version" || true)
  code=$(awk 'NR==1{print $2}' <<<"$out" || echo "000")
  pool=$(grep -i '^X-App-Pool:' <<<"$out" | awk '{print tolower($2)}' || echo "")
  if [ "$code" != "200" ]; then
    bad=$((bad + 1))
  else
    if [ "$pool" = "green" ]; then
      green_count=$((green_count + 1))
    fi
  fi
  sleep "${ITER_INTERVAL}"
done

echo "Results: total=$total, green=$green_count, bad=$bad"
# Fail conditions
if [ "$bad" -ne 0 ]; then
  echo "FAIL: non-200 responses detected (bad=$bad)"
  curl -s -X POST "$BLUE_CHAOS_STOP" >/dev/null || true
  exit 4
fi

# percentage green
pct=$(( (green_count * 100) / total ))
echo "Green percentage: ${pct}%"

if [ "$pct" -lt 95 ]; then
  echo "FAIL: green percentage below 95% (${pct}%)"
  curl -s -X POST "$BLUE_CHAOS_STOP" >/dev/null || true
  exit 5
fi

echo "5) Restore Blue"
curl -s -X POST "$BLUE_CHAOS_STOP" >/dev/null || true

echo "Verification succeeded: failover occurred and served from green with >=95%."
exit 0
