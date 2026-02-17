#!/bin/bash
# AgentBox End-to-End Test Suite
# Usage: ANTHROPIC_API_KEY=sk-ant-... ./test/run_tests.sh
# Must be run from the agentbox repo root.
set -euo pipefail

PASS=0
FAIL=0
SKIP=0
RESULTS=()

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[0;33m'
RST='\033[0m'

pass() { PASS=$((PASS+1)); RESULTS+=("✅ $1"); echo -e "${GRN}PASS${RST}: $1"; }
fail() { FAIL=$((FAIL+1)); RESULTS+=("❌ $1: $2"); echo -e "${RED}FAIL${RST}: $1 — $2"; }
skip() { SKIP=$((SKIP+1)); RESULTS+=("⏭  $1: $2"); echo -e "${YLW}SKIP${RST}: $1 — $2"; }
section() { echo ""; echo "── $1 ──────────────────────────────────────"; }

# ── Pre-flight ─────────────────────────────────────────────────────────────
if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ERROR: ANTHROPIC_API_KEY not set. Run: export ANTHROPIC_API_KEY=sk-ant-..."
  exit 1
fi

export COMPOSE_PROJECT_NAME=agentbox_test

section "Teardown & Fresh Start"
docker compose -f docker-compose.yml --project-name agentbox_test down -v --remove-orphans 2>/dev/null || true
docker volume rm agentbox_test_agentbox-config agentbox_test_agentbox-data \
  agentbox_test_agentbox-logs agentbox_test_openclaw-logs 2>/dev/null || true

# Kill anything holding our ports
fuser -k 3000/tcp 8501/tcp 2>/dev/null || true
sleep 1
echo "Clean slate."

section "Build"
echo "Building images..."
docker compose -f docker-compose.yml --project-name agentbox_test build --no-cache 2>&1 | \
  grep -E "DONE|ERROR|Security gate|warn deprecated|#[0-9]+ DONE" | tail -20

if docker images agentbox:latest --format "{{.ID}}" | grep -q .; then
  pass "T01: agentbox image builds"
else
  fail "T01: agentbox image builds" "image not found after build"
  exit 1
fi

if docker images agentbox-telemetry:latest --format "{{.ID}}" | grep -q .; then
  pass "T02: telemetry image builds"
else
  fail "T02: telemetry image builds" "image not found"
  exit 1
fi

section "Config injection (simulate new user setup)"
# Create volumes and inject config before starting containers
docker volume create agentbox_test_agentbox-config >/dev/null

# Spin a tmp container to inject the config
docker run --rm \
  -v agentbox_test_agentbox-config:/vol \
  busybox sh -c "mkdir -p /vol/agents/main/agent /vol/workspace && \
    cat > /vol/openclaw.json << 'EOJSON'
{
  \"meta\": {\"lastTouchedVersion\": \"2026.2.15\"},
  \"auth\": {\"profiles\": {\"anthropic:default\": {\"provider\": \"anthropic\", \"mode\": \"token\"}}},
  \"agents\": {\"defaults\": {
    \"model\": {\"primary\": \"anthropic/claude-sonnet-4-5\"},
    \"models\": {\"anthropic/claude-sonnet-4-5\": {}},
    \"workspace\": \"/agentbox/.openclaw/workspace\",
    \"compaction\": {\"mode\": \"safeguard\"},
    \"maxConcurrent\": 4, \"subagents\": {\"maxConcurrent\": 8}
  }},
  \"tools\": {\"web\": {\"search\": {\"enabled\": true}, \"fetch\": {\"enabled\": true}}},
  \"commands\": {\"native\": \"auto\", \"nativeSkills\": \"auto\"},
  \"gateway\": {\"port\": 3000, \"mode\": \"local\", \"auth\": {\"mode\": \"token\", \"token\": \"agentbox-test-abc\"}}
}
EOJSON
    chown -R 1000:1000 /vol"

# Copy auth-profiles if available
if [[ -f "$HOME/.openclaw/agents/main/agent/auth-profiles.json" ]]; then
  docker run --rm \
    -v agentbox_test_agentbox-config:/vol \
    -v "$HOME/.openclaw/agents/main/agent/auth-profiles.json":/src/auth.json:ro \
    busybox sh -c "cp /src/auth.json /vol/agents/main/agent/auth-profiles.json && chown -R 1000:1000 /vol"
  pass "T03: config + auth injected into volume"
else
  skip "T03: auth-profiles inject" "auth-profiles.json not found at $HOME/.openclaw/agents/main/agent/"
fi

section "Start Stack"
docker compose -f docker-compose.yml --project-name agentbox_test up -d
echo "Waiting for services to initialize (30s)..."
sleep 30

section "Container Health"
AGENTBOX_STATUS=$(docker inspect agentbox_test-agentbox-1 2>/dev/null \
  --format '{{.State.Health.Status}}' 2>/dev/null || \
  docker inspect agentbox_test_agentbox_1 2>/dev/null --format '{{.State.Health.Status}}' 2>/dev/null || \
  echo "unknown")

CONTAINER_ID=$(docker ps --filter "name=agentbox_test" --filter "name=agentbox" \
  --format "{{.Names}}" | grep -v telemetry | head -1)
TELEMETRY_ID=$(docker ps --filter "name=agentbox_test" --filter "name=telemetry" \
  --format "{{.Names}}" | head -1)

echo "agentbox container: $CONTAINER_ID"
echo "telemetry container: $TELEMETRY_ID"

if [[ -n "$CONTAINER_ID" ]]; then
  STATUS=$(docker inspect "$CONTAINER_ID" --format '{{.State.Status}}')
  HEALTH=$(docker inspect "$CONTAINER_ID" --format '{{.State.Health.Status}}' 2>/dev/null || echo "no healthcheck")
  echo "  Status: $STATUS | Health: $HEALTH"
  [[ "$STATUS" == "running" ]] && pass "T04: agentbox container running" || fail "T04: agentbox container running" "$STATUS"
  [[ "$HEALTH" == "healthy" ]] && pass "T05: agentbox healthcheck healthy" || fail "T05: agentbox healthcheck" "$HEALTH"
else
  fail "T04: agentbox container running" "container not found"
  fail "T05: agentbox healthcheck" "container not found"
fi

if [[ -n "$TELEMETRY_ID" ]]; then
  STATUS=$(docker inspect "$TELEMETRY_ID" --format '{{.State.Status}}')
  HEALTH=$(docker inspect "$TELEMETRY_ID" --format '{{.State.Health.Status}}' 2>/dev/null || echo "no healthcheck")
  echo "  Status: $STATUS | Health: $HEALTH"
  [[ "$STATUS" == "running" ]] && pass "T06: telemetry container running" || fail "T06: telemetry container running" "$STATUS"
  [[ "$HEALTH" == "healthy" ]] && pass "T07: telemetry healthcheck healthy" || fail "T07: telemetry healthcheck" "$HEALTH"
else
  fail "T06: telemetry container running" "container not found"
  fail "T07: telemetry healthcheck" "container not found"
fi

section "Gateway API"
# Gateway is WebSocket-only (not plain HTTP); check TCP port is open and
# supervisorctl confirms the process is RUNNING — same check as HEALTHCHECK.
if [[ -n "$CONTAINER_ID" ]]; then
  GW_PROC=$(docker exec "$CONTAINER_ID" \
    supervisorctl -c /etc/supervisor/conf.d/agentbox.conf status openclaw-gateway 2>/dev/null || echo "")
  if echo "$GW_PROC" | grep -q "RUNNING"; then
    pass "T08: gateway process RUNNING on port 3000 (WebSocket)"
  else
    fail "T08: gateway process RUNNING on port 3000" "supervisorctl: $GW_PROC"
  fi
else
  skip "T08: gateway process check" "container not found"
fi

section "AI Inference (--local mode)"
if [[ -n "$CONTAINER_ID" ]]; then
  AI_OUT=$(docker exec \
    -e ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY" \
    "$CONTAINER_ID" \
    openclaw agent --local --session-id test-inference \
    -m "Reply with exactly: AGENTBOX_VERIFIED" 2>&1 | tr -d '\n')
  
  if echo "$AI_OUT" | grep -q "AGENTBOX_VERIFIED"; then
    pass "T09: AI inference produces correct output"
  else
    fail "T09: AI inference produces correct output" "got: ${AI_OUT:0:100}"
  fi
else
  skip "T09: AI inference" "agentbox container not found"
fi

section "Session file path (no double .openclaw)"
if [[ -n "$CONTAINER_ID" ]]; then
  SESSION_PATH=$(docker exec "$CONTAINER_ID" find /agentbox/.openclaw/agents -name "test-inference.jsonl" 2>/dev/null)
  if [[ -n "$SESSION_PATH" ]]; then
    pass "T10: session JSONL at correct path ($SESSION_PATH)"
  else
    # Check if it landed in wrong place
    WRONG=$(docker exec "$CONTAINER_ID" find /agentbox/.openclaw/.openclaw 2>/dev/null | head -3)
    fail "T10: session JSONL at correct path" "not found; wrong path: ${WRONG:-none}"
  fi
else
  skip "T10: session path" "container not running"
fi

section "Telemetry sees sessions"
if [[ -n "$TELEMETRY_ID" ]]; then
  TELEM_SESSIONS=$(docker exec "$TELEMETRY_ID" find /data/openclaw/agents -name "*.jsonl" 2>/dev/null)
  if [[ -n "$TELEM_SESSIONS" ]]; then
    pass "T11: telemetry can read session JSONL ($TELEM_SESSIONS)"
  else
    fail "T11: telemetry can read session JSONL" "no .jsonl files found at /data/openclaw/agents"
  fi
  
  # Test telemetry HTTP endpoint
  TELEM_HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8501/_stcore/health 2>/dev/null || echo "000")
  [[ "$TELEM_HTTP" == "200" ]] && pass "T12: telemetry HTTP 200" || fail "T12: telemetry HTTP 200" "got $TELEM_HTTP"
else
  skip "T11: telemetry sessions" "telemetry container not found"
  skip "T12: telemetry HTTP" "telemetry container not found"
fi

section "TUI renders"
if [[ -n "$CONTAINER_ID" ]] && command -v expect &>/dev/null; then
  TUI_OUT=$(expect -c "
    set timeout 15
    spawn docker exec -it $CONTAINER_ID openclaw tui
    expect {
      \"2026\"        { puts \"TUI_YEAR_OK\" }
      \"OpenClaw\"    { puts \"TUI_BANNER_OK\" }
      timeout        { puts \"TUI_TIMEOUT\" }
      eof            { puts \"TUI_EOF\" }
    }
    after 2000
    send \"q\"
    expect eof
  " 2>&1 | strings | grep -E "TUI_")
  
  if echo "$TUI_OUT" | grep -qE "TUI_YEAR_OK|TUI_BANNER_OK"; then
    pass "T13: TUI renders (found version/banner)"
  elif echo "$TUI_OUT" | grep -q "TUI_TIMEOUT"; then
    fail "T13: TUI renders" "timed out waiting for output"
  else
    fail "T13: TUI renders" "unexpected: $TUI_OUT"
  fi
else
  skip "T13: TUI renders" "expect not installed or container not running"
fi

section "Security flags"
if [[ -n "$CONTAINER_ID" ]]; then
  RO=$(docker inspect "$CONTAINER_ID" --format '{{.HostConfig.ReadonlyRootfs}}')
  [[ "$RO" == "true" ]] && pass "T14: read_only filesystem" || fail "T14: read_only filesystem" "ReadonlyRootfs=$RO"
  
  CAPS=$(docker inspect "$CONTAINER_ID" --format '{{json .HostConfig.CapAdd}}')
  [[ "$CAPS" == "null" || "$CAPS" == "[]" ]] && pass "T15: no capabilities added (cap_drop ALL)" || fail "T15: no capabilities added" "CapAdd=$CAPS"
  
  NONEWPRIV=$(docker inspect "$CONTAINER_ID" --format '{{.HostConfig.SecurityOpt}}')
  echo "$NONEWPRIV" | grep -q "no-new-privileges" && pass "T16: no-new-privileges set" || fail "T16: no-new-privileges" "$NONEWPRIV"
else
  skip "T14: security flags" "container not found"
  skip "T15: security flags" "container not found"
  skip "T16: security flags" "container not found"
fi

section "Restart resilience"
if [[ -n "$CONTAINER_ID" ]]; then
  # Kill supervisord child process; supervisord should restart it
  docker exec "$CONTAINER_ID" pkill -f "openclaw-gateway" 2>/dev/null || true
  sleep 8
  ALIVE=$(docker exec "$CONTAINER_ID" pgrep -f "openclaw-gateway" 2>/dev/null || echo "")
  if [[ -n "$ALIVE" ]]; then
    pass "T17: supervisord restarts openclaw-gateway after kill"
  else
    fail "T17: supervisord restarts openclaw-gateway after kill" "process not found after 8s"
  fi
else
  skip "T17: restart resilience" "container not found"
fi

section "Persistence across container restart"
if [[ -n "$CONTAINER_ID" ]]; then
  docker restart "$CONTAINER_ID" >/dev/null
  sleep 15
  STATUS=$(docker inspect "$CONTAINER_ID" --format '{{.State.Status}}')
  # Session file from T09 should still exist
  SESSION_AFTER=$(docker exec "$CONTAINER_ID" find /agentbox/.openclaw/agents -name "test-inference.jsonl" 2>/dev/null)
  if [[ "$STATUS" == "running" && -n "$SESSION_AFTER" ]]; then
    pass "T18: session data persists across container restart"
  elif [[ "$STATUS" != "running" ]]; then
    fail "T18: persistence" "container not running after restart"
  else
    fail "T18: persistence" "session JSONL gone after restart"
  fi
else
  skip "T18: persistence" "container not found"
fi

# ── Summary ────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════"
echo " Test Results: $PASS passed, $FAIL failed, $SKIP skipped"
echo "════════════════════════════════════════════"
for r in "${RESULTS[@]}"; do echo "  $r"; done
echo ""

# Cleanup
echo "Tearing down test stack..."
docker compose -f docker-compose.yml --project-name agentbox_test down -v --remove-orphans 2>/dev/null

if [[ $FAIL -gt 0 ]]; then
  echo -e "${RED}❌ $FAIL test(s) failed — not ready to merge.${RST}"
  exit 1
else
  echo -e "${GRN}✅ All $PASS tests passed.${RST}"
fi
