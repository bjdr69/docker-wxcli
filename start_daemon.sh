#!/usr/bin/env bash
# start_daemon.sh — Phase 5: Initialize wx-cli, start daemon, and smoke test
# Run INSIDE the wechat-selkies container.
# PREREQUISITE: Phase 4 (extract_keys.sh) must have completed successfully.
# Usage: docker exec -it wechat-selkies bash /config/start_daemon.sh

set -euo pipefail

WX_CLI="/config/tools/wx-cli"
WX_CONFIG="/config/.wx-cli/config.json"
ALL_KEYS="/config/.wx-cli/all_keys.json"

echo "=== Phase 5: wx-cli Daemon Startup and Smoke Test ==="

# --- Step 0: Prerequisites ---
echo "[0] Checking prerequisites..."

if [ ! -f "$WX_CLI" ] || [ ! -x "$WX_CLI" ]; then
    echo "  ERROR: wx-cli binary not found or not executable at $WX_CLI"
    echo "  Run setup_env.sh first."
    exit 1
fi

if [ ! -f "$ALL_KEYS" ]; then
    echo "  ERROR: all_keys.json not found at $ALL_KEYS"
    echo "  Run extract_keys.sh first (Phase 4)."
    exit 1
fi

if [ ! -s "$ALL_KEYS" ]; then
    echo "  ERROR: all_keys.json is empty. Key extraction may have failed."
    exit 1
fi

echo "  wx-cli binary: $WX_CLI"
echo "  Config: $WX_CONFIG"
echo "  Keys: $ALL_KEYS ($(wc -c < "$ALL_KEYS") bytes)"

# --- Step 1: Initialize wx-cli ---
echo "[1] Running wx init..."
"$WX_CLI" init 2>&1 || {
    echo "  WARNING: wx init returned non-zero. This may be OK for first run."
}
echo "  Init complete"

# --- Step 2: Start daemon ---
echo "[2] Starting wx daemon..."
# Check if daemon is already running
if "$WX_CLI" daemon status 2>/dev/null | grep -q 'running'; then
    echo "  Daemon already running. Restarting..."
    "$WX_CLI" daemon stop 2>/dev/null || true
    sleep 2
fi

"$WX_CLI" daemon start 2>&1 &
DAEMON_PID=$!
sleep 3

# Verify daemon started
if kill -0 "$DAEMON_PID" 2>/dev/null; then
    echo "  Daemon started with PID: $DAEMON_PID"
else
    echo "  ERROR: Daemon failed to start"
    exit 1
fi

# --- Step 3: Smoke tests ---
SMOKE_PASS=0
SMOKE_FAIL=0

echo "[3] Running smoke tests..."

run_smoke() {
    local test_name="$1"
    local cmd="$2"
    echo "  [$test_name] $cmd"
    if OUTPUT=$(eval "$cmd" 2>&1); then
        echo "    PASS"
        echo "    ${OUTPUT:0:500}"
        SMOKE_PASS=$((SMOKE_PASS + 1))
    else
        echo "    FAIL: $OUTPUT"
        SMOKE_FAIL=$((SMOKE_FAIL + 1))
    fi
}

# Test 1: List recent sessions
echo ""
echo "  --- Test 1: wx sessions ---"
if "$WX_CLI" sessions 2>&1 | head -20; then
    echo "  [sessions] PASS"
    SMOKE_PASS=$((SMOKE_PASS + 1))
else
    echo "  [sessions] FAIL"
    SMOKE_FAIL=$((SMOKE_FAIL + 1))
fi

# Test 2: Search with JSON output
echo ""
echo "  --- Test 2: wx search ---"
SEARCH_TERM="${1:-你好}"
if OUTPUT=$("$WX_CLI" search "$SEARCH_TERM" --json 2>&1); then
    echo "  [search] PASS"
    echo "  Result: $(echo "$OUTPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(f"got {len(d) if isinstance(d,list) else 1} results")' 2>/dev/null || echo "$OUTPUT" | head -5)"
    SMOKE_PASS=$((SMOKE_PASS + 1))
else
    echo "  [search] FAIL: $OUTPUT"
    SMOKE_FAIL=$((SMOKE_FAIL + 1))
fi

# --- Summary ---
echo ""
echo "=== Smoke Test Results ==="
echo "  Passed: $SMOKE_PASS"
echo "  Failed: $SMOKE_FAIL"

if [ "$SMOKE_FAIL" -gt 0 ]; then
    echo ""
    echo "  Some tests failed. Common issues:"
    echo "  - Cache not built yet (wx init may need more time)"
    echo "  - Keys may be incorrect (re-run extract_keys.sh)"
    echo "  - WeChat may need to be actively logged in"
fi

echo ""
echo "=== Daemon is Running ==="
echo "  Stop daemon:     wx daemon stop"
echo "  Check status:    wx daemon status"
echo "  Query contacts:  wx sessions"
echo "  Search messages: wx search 'keyword' --json"
