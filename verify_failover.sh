#!/usr/bin/env bash
#
# Improved Blue-Green Failover Verification Script
# Works reliably on EC2 (handles latency, retries, and chaos endpoints)
#

# === Strict mode but safe ===
set -o pipefail

# === Configurable ports (via env or defaults) ===
NGINX_PORT="${NGINX_PORT:-8080}"
BLUE_PORT="${BLUE_PORT:-8081}"
GREEN_PORT="${GREEN_PORT:-8082}"
CHECK_DURATION="${CHECK_DURATION:-10}"
ITER_INTERVAL="${ITER_INTERVAL:-0.3}"

BASE_URL="http://localhost:${NGINX_PORT}"
BLUE_CHAOS="http://localhost:${BLUE_PORT}/chaos/start?mode=error"
BLUE_CHAOS_STOP="http://localhost:${BLUE_PORT}/chaos/stop"
GREEN_CHAOS_STOP="http://localhost:${GREEN_PORT}/chaos/stop"

echo "=== 🔍 Verifying Blue-Green Failover ==="
echo "NGINX_PORT=$NGINX_PORT | BLUE_PORT=$BLUE_PORT | GREEN_PORT=$GREEN_PORT"
echo "------------------------------------------------------------"

# === Step 0: Reset any prior chaos ===
echo "Resetting any previous chaos states..."
curl -s -X POST "$BLUE_CHAOS_STOP" >/dev/null 2>&1 || true
curl -s -X POST "$GREEN_CHAOS_STOP" >/dev/null 2>&1 || true
sleep 1

# === Step 1: Baseline check (expect Blue active) ===
echo ""
echo "1️⃣  Baseline check (should be BLUE active)"
resp_headers=$(curl -sI --max-time 5 "${BASE_URL}/version" || echo "")
if grep -qi "X-App-Pool: blue" <<<"$resp_headers"; then
  echo "✅  Baseline confirmed: BLUE is active"
else
  echo "⚠️  Baseline check did not return BLUE pool"
  echo "$resp_headers"
  echo "Aborting: Nginx may not be routing to Blue."
  exit 1
fi

# === Step 2: Trigger chaos on Blue ===
echo ""
echo "2️⃣  Triggering chaos mode on BLUE..."
if curl -s -X POST "$BLUE_CHAOS" >/dev/null 2>&1; then
  echo "✅  Chaos mode activated on Blue."
else
  echo "⚠️  Failed to activate chaos mode on Blue — continuing anyway."
fi
sleep 2

# === Step 3: Begin failover verification loop ===
echo ""
echo "3️⃣  Checking responses for ${CHECK_DURATION}s..."
end=$((SECONDS + CHECK_DURATION))
total=0
green_count=0
blue_count=0
errors=0

while [ $SECONDS -lt $end ]; do
  ((total++))
  resp=$(curl -s -i --max-time 5 "${BASE_URL}/version" || echo "ERROR")
  
  if [[ "$resp" == "ERROR" ]]; then
    ((errors++))
    echo "❌  [$total] Request failed (timeout or connection error)"
  else
    code=$(awk 'NR==1{print $2}' <<<"$resp" || echo "000")
    pool=$(grep -i '^X-App-Pool:' <<<"$resp" | awk '{print tolower($2)}' | tr -d '\r' || echo "")
    if [[ "$code" != "200" ]]; then
      ((errors++))
      echo "❌  [$total] HTTP $code (non-200)"
    elif [[ "$pool" == "green" ]]; then
      ((green_count++))
      echo "🟢  [$total] Pool: green ✓"
    elif [[ "$pool" == "blue" ]]; then
      ((blue_count++))
      echo "🔵  [$total] Pool: blue (still responding)"
    else
      ((errors++))
      echo "⚠️  [$total] Unknown pool or header missing"
    fi
  fi
  sleep "$ITER_INTERVAL"
done

# === Step 4: Summary results ===
echo ""
echo "=== 📊 Summary Results ==="
echo "Total requests: $total"
echo "Green responses: $green_count"
echo "Blue responses:  $blue_count"
echo "Errors:          $errors"

green_pct=$(( (green_count * 100) / total ))
echo "Green percentage: ${green_pct}%"
echo ""

# === Step 5: Evaluate success criteria ===
if (( errors == 0 )) && (( green_pct >= 95 )); then
  echo "✅ PASS: Failover successful — ≥95% requests served from GREEN with 0 errors."
else
  echo "❌ FAIL: Conditions not met — errors=$errors, green=${green_pct}%"
  echo "🧩 Check Nginx health_check config and upstream fail_timeout."
fi

# === Step 6: Restore BLUE ===
echo ""
echo "6️⃣  Restoring BLUE instance..."
curl -s -X POST "$BLUE_CHAOS_STOP" >/dev/null 2>&1 || true
curl -s -X POST "$GREEN_CHAOS_STOP" >/dev/null 2>&1 || true
echo "✅  Blue and Green restored to normal."

echo ""
echo "=== ✅ Verification complete ==="
exit 0
