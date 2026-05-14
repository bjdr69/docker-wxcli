#!/usr/bin/env bash
# extract_keys.sh — Phase 4: wcdb-key-tool key extraction and conversion
# Run INSIDE the wechat-selkies container.
# PREREQUISITE: WeChat must be running (via browser WebRTC/VNC session).
# Usage: docker exec -it wechat-selkies bash /config/extract_keys.sh

set -euo pipefail

TOOLS_DIR="/config/tools"
WCDB_KEY_TOOL="$TOOLS_DIR/wcdb-key-tool/wcdb_key_tool.py"
ALL_KEYS_FILE="/config/.wx-cli/all_keys.json"

echo "=== Phase 4: WeChat Key Extraction Workflow ==="

# --- Step 1: Verify prerequisites ---
echo "[1] Verifying prerequisites..."

if [ ! -f "$WCDB_KEY_TOOL" ]; then
    echo "  ERROR: wcdb_key_tool.py not found at $WCDB_KEY_TOOL"
    echo "  Run setup_env.sh first."
    exit 1
fi

# Supported wechat binary names per PRD
WECHAT_BIN=""
for candidate in /opt/wechat-beta/wechat /opt/wechat-universal/wechat /usr/bin/wechat; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
        WECHAT_BIN="$candidate"
        break
    fi
done

if [ -z "$WECHAT_BIN" ]; then
    echo "  WARNING: WeChat binary not found at known paths."
    # Try to find it
    WECHAT_BIN=$(find /opt -name 'wechat' -type f -executable 2>/dev/null | head -1 || true)
    if [ -z "$WECHAT_BIN" ]; then
        echo "  ERROR: Cannot locate WeChat binary. Is WeChat installed in this container?"
        exit 1
    fi
fi
echo "  WeChat binary: $WECHAT_BIN"

# --- Step 2: Find running WeChat process ---
echo "[2] Locating running WeChat process..."
WECHAT_PID=$(pgrep -f 'wechat' | head -1 || true)
if [ -z "$WECHAT_PID" ]; then
    echo ""
    echo "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "  !  WECHAT IS NOT RUNNING                                !"
    echo "  !                                                       !"
    echo "  !  Action required:                                     !"
    echo "  !  1. Open http://localhost:3000 in your browser         !"
    echo "  !  2. Launch WeChat inside the noVNC desktop             !"
    echo "  !  3. Log in, keep WeChat window open                    !"
    echo "  !  4. Re-run this script                                !"
    echo "  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo ""
    exit 1
fi
echo "  WeChat PID: $WECHAT_PID"

# Show process tree for diagnostics
echo "  Process tree:"
ps --ppid "$WECHAT_PID" -o pid,comm 2>/dev/null || echo "    (no children found)"
# Also check for any zombie/defunct children
WECHAT_TREE_PIDS=$(pstree -p "$WECHAT_PID" 2>/dev/null | grep -oP '\d+' || echo "$WECHAT_PID")

# --- Step 3: Run wcdb_key_tool extraction (GDB breakpoint, auto-manages process) ---
echo "[3] Running wcdb_key_tool.py extract..."
echo "  (The tool will wait up to 120s for a WeChat re-login trigger)"
cd "$TOOLS_DIR/wcdb-key-tool"

EXTRACT_OUTPUT=$(python3 "$WCDB_KEY_TOOL" extract 2>&1) || {
    echo "  ERROR: wcdb_key_tool extraction failed"
    echo "  Output:"
    echo "$EXTRACT_OUTPUT"
    echo ""
    echo "  Potential issues:"
    echo "  - Need to re-login WeChat to trigger breakpoint"
    echo "  - SYS_PTRACE capability not available (check docker-compose cap_add)"
    exit 1
}

echo "$EXTRACT_OUTPUT"

# --- Step 4: Convert output to wx-cli all_keys.json format ---
echo "[4] Converting keys to wx-cli format..."

RAW_KEYS=$(echo "$EXTRACT_OUTPUT" | python3 -c "
import sys, json, re
text = sys.stdin.read()
# wcdb-key-tool outputs JSON dict with 'keys' array
match = re.search(r'\{.*\}', text, re.DOTALL)
if match:
    try:
        data = json.loads(match.group())
        keys = data.get('keys', [data] if isinstance(data, dict) else [])
        result = {}
        for item in keys if isinstance(keys, list) else [keys]:
            db_path = item.get('db_path', item.get('path', item.get('db', '')))
            key = item.get('key', item.get('aes_key', item.get('aesKey', '')))
            if db_path and key:
                result[db_path] = key
        if result:
            print(json.dumps(result, indent=2, ensure_ascii=False))
        else:
            # Save the raw JSON as-is for manual inspection
            print(json.dumps(data, indent=2, ensure_ascii=False))
    except json.JSONDecodeError:
        print(json.dumps({'raw_output': text.strip()}, indent=2))
else:
    print(json.dumps({'raw_output': text.strip()}, indent=2))
" 2>/dev/null) || {
    echo "  WARNING: Could not parse extraction output as JSON"
    RAW_KEYS=$(echo "$EXTRACT_OUTPUT" | python3 -c "
import sys, json
print(json.dumps({'raw_output': sys.stdin.read().strip()}, indent=2))
")
}

# Write to config directory
echo "$RAW_KEYS" > "$ALL_KEYS_FILE"
chmod 600 "$ALL_KEYS_FILE"

echo "  Keys written to $ALL_KEYS_FILE"
echo "  Key count: $(echo "$RAW_KEYS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d))" 2>/dev/null || echo "unknown")"

# --- Step 6: Verify ---
echo "[6] Verifying extraction..."
if [ -s "$ALL_KEYS_FILE" ]; then
    echo "  all_keys.json exists and is non-empty"
    echo "  Permissions: $(stat -c '%a %n' "$ALL_KEYS_FILE")"
else
    echo "  ERROR: all_keys.json is empty. Extraction failed."
    exit 1
fi

echo ""
echo "=== Key Extraction Complete ==="
echo "  Keys saved to: $ALL_KEYS_FILE"
echo "  Ready for Phase 5: wx-cli daemon startup"
