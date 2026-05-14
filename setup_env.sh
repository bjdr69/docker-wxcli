#!/usr/bin/env bash
# setup_env.sh — Verify environment (dependencies pre-installed in Docker image)
# Run this INSIDE the wechat-selkies container to verify toolchain.
# Usage: docker exec -it wechat-selkies bash /config/setup_env.sh

set -euo pipefail

echo "=== Environment Verification ==="
echo ""

PASS=0
FAIL=0

check() {
    local name="$1"
    local cmd="$2"
    if eval "$cmd" >/dev/null 2>&1; then
        echo "  [PASS] $name"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $name"
        FAIL=$((FAIL + 1))
    fi
}

echo "--- System Packages ---"
check "gdb" "gdb --version"
check "python3" "python3 --version"
check "sqlcipher" "sqlcipher --version"
check "wget" "wget --version"

echo "--- Python Packages ---"
check "sqlcipher3" "python3 -c 'import sqlcipher3'"
check "pycryptodome (Crypto)" "python3 -c 'import Crypto'"

echo "--- Tools ---"
check "wcdb-key-tool" "test -d /config/tools/wcdb-key-tool -a -f /config/tools/wcdb-key-tool/wcdb_key_tool.py"
check "wx-cli" "/config/tools/wx-cli --version"

# Optionally pull latest wcdb-key-tool
if [ -d /config/tools/wcdb-key-tool/.git ]; then
    echo ""
    echo "--- Update Check ---"
    git -C /config/tools/wcdb-key-tool fetch --depth 1 origin main 2>/dev/null || true
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
echo "  (Dependencies are baked into the Docker image;"
echo "   no apt/pip install needed after container rebuild.)"
