#!/usr/bin/env bash
# setup_env.sh — Phase 2: Container dependency injection
# Run this INSIDE the wechat-selkies container after it starts.
# Usage: docker exec -it wechat-selkies bash /config/setup_env.sh

set -euo pipefail

TOOLS_DIR="/config/tools"
mkdir -p "$TOOLS_DIR"

echo "=== [1/5] Updating apt sources and installing system packages ==="
apt-get update -qq
apt-get install -y -qq gdb python3 python3-pip sqlcipher git wget curl

echo "=== [2/5] Installing Python dependencies ==="
pip3 install --no-cache-dir --break-system-packages sqlcipher3 pycryptodome

echo "=== [3/5] Downloading wcdb-key-tool ==="
if [ ! -d "$TOOLS_DIR/wcdb-key-tool" ]; then
    git clone --depth 1 https://github.com/bjdr69/wcdb-key-tool.git "$TOOLS_DIR/wcdb-key-tool"
else
    echo "  wcdb-key-tool already exists, skipping clone. Pull latest with: git -C $TOOLS_DIR/wcdb-key-tool pull"
fi
chmod +x "$TOOLS_DIR/wcdb-key-tool/wcdb_key_tool.py"

echo "=== [4/5] Downloading wx-cli Linux binary ==="
# wx-cli binary — replace URL with actual release URL as needed
WX_CLI_URL="${WX_CLI_URL:-https://github.com/your-org/wx-cli/releases/latest/download/wx-cli-linux-amd64}"
if [ ! -f "$TOOLS_DIR/wx-cli" ]; then
    if wget -q --show-progress -O "$TOOLS_DIR/wx-cli" "$WX_CLI_URL" 2>/dev/null; then
        echo "  wx-cli downloaded successfully"
    else
        echo "  WARNING: Failed to download wx-cli from $WX_CLI_URL"
        echo "  Place the wx-cli binary manually at $TOOLS_DIR/wx-cli"
    fi
else
    echo "  wx-cli already exists, skipping download"
fi
chmod +x "$TOOLS_DIR/wx-cli" 2>/dev/null || true

echo "=== [5/5] Verifying installations ==="
echo "--- gdb version ---"
gdb --version | head -1 || echo "  ERROR: gdb not found"
echo "--- python3 version ---"
python3 --version || echo "  ERROR: python3 not found"
echo "--- sqlcipher ---"
sqlcipher --version 2>/dev/null || dpkg -l | grep sqlcipher || echo "  WARNING: sqlcipher check failed"
echo "--- wcdb-key-tool ---"
ls -la "$TOOLS_DIR/wcdb-key-tool/wcdb_key_tool.py" 2>/dev/null || echo "  WARNING: wcdb_key_tool.py not found"
echo "--- wx-cli ---"
"$TOOLS_DIR/wx-cli" --version 2>/dev/null || echo "  WARNING: wx-cli not yet available"

# Add tools to PATH via profile
PROFILE_D="/etc/profile.d/wx-tools.sh"
if [ ! -f "$PROFILE_D" ]; then
    cat > "$PROFILE_D" <<'EOF'
export PATH="/config/tools:$PATH"
EOF
    chmod 644 "$PROFILE_D"
    echo "  Added /config/tools to system PATH"
fi

echo ""
echo "=== setup_env.sh complete ==="
echo "Re-source your shell: source /etc/profile.d/wx-tools.sh"
echo "Or restart your shell session"
