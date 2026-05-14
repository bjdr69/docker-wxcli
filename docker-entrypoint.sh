#!/usr/bin/with-contenv bash
# docker-entrypoint.sh — Runs on every container start via s6 cont-init.d
# Syncs pre-built tools to /config/tools/ and sets up PATH

TOOLS_DIR="/config/tools"

# Sync wcdb-key-tool if not already present
if [ -d "/opt/wcdb-key-tool" ] && [ ! -d "$TOOLS_DIR/wcdb-key-tool" ]; then
    mkdir -p "$TOOLS_DIR"
    cp -r /opt/wcdb-key-tool "$TOOLS_DIR/"
    echo "[wxcli-init] wcdb-key-tool synced to /config/tools/"
fi

# Sync wx-cli if not already present
if [ -f "/usr/local/bin/wx-cli" ] && [ ! -f "$TOOLS_DIR/wx-cli" ]; then
    mkdir -p "$TOOLS_DIR"
    cp /usr/local/bin/wx-cli "$TOOLS_DIR/wx-cli"
    echo "[wxcli-init] wx-cli synced to /config/tools/"
fi

# Ensure PATH includes /config/tools
PROFILE_D="/etc/profile.d/wx-tools.sh"
if [ ! -f "$PROFILE_D" ]; then
    cat > "$PROFILE_D" <<'EOF'
export PATH="/config/tools:$PATH"
EOF
    chmod 644 "$PROFILE_D"
    echo "[wxcli-init] Added /config/tools to PATH"
fi
