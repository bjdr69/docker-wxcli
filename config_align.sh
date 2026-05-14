#!/usr/bin/env bash
# config_align.sh — Phase 3: Auto-detect wxid and generate wx-cli config
# Run INSIDE the wechat-selkies container.
# Usage: docker exec -it wechat-selkies bash /config/config_align.sh

set -euo pipefail

WX_DATA_BASE=""
# Search multiple possible xwechat_files locations
for candidate in /config/xwechat_files /config/Documents/WeChat_Data/xwechat_files /config/.xwechat; do
    if [ -d "$candidate" ]; then
        WX_DATA_BASE="$candidate"
        break
    fi
done

if [ -z "$WX_DATA_BASE" ]; then
    echo "  ERROR: Cannot find xwechat_files directory."
    echo "  Tried: /config/xwechat_files, /config/Documents/WeChat_Data/xwechat_files, /config/.xwechat"
    echo "  Launch WeChat in the browser (http://localhost:3000) and log in first."
    exit 1
fi
WX_CONFIG_DIR="/config/.wx-cli"
WX_CLI_HOME="$HOME/.wx-cli"

echo "=== Phase 3: Configuration Alignment ==="

# --- Step 1: Find wxid ---
echo "[1] Scanning for WeChat user directory (wxid)..."
WXID=""
if [ -d "$WX_DATA_BASE" ]; then
    # wxid directories look like: wxid_xxxxxxxxxxxxxxxx
    CANDIDATES=$(ls "$WX_DATA_BASE" 2>/dev/null | grep -E '^wxid_' || true)
    CANDIDATE_COUNT=$(echo "$CANDIDATES" | grep -c 'wxid_' || true)
    if [ "$CANDIDATE_COUNT" -eq 1 ]; then
        WXID="$CANDIDATES"
        echo "  Found single wxid: $WXID"
    elif [ "$CANDIDATE_COUNT" -gt 1 ]; then
        echo "  Multiple wxid directories found:"
        echo "$CANDIDATES"
        WXID=$(echo "$CANDIDATES" | head -1)
        echo "  Using first one: $WXID"
    fi
fi

if [ -z "$WXID" ]; then
    echo "  ERROR: No wxid directory found under $WX_DATA_BASE"
    echo "  Make sure WeChat has been launched at least once and xwechat_files are mounted."
    exit 1
fi

# --- Step 2: Verify db_storage path ---
# WeChat v4+ stores DBs in db_storage; older versions may use Msg/
DB_DIR="$WX_DATA_BASE/$WXID/db_storage"
if [ ! -d "$DB_DIR" ]; then
    DB_DIR="$WX_DATA_BASE/$WXID/Msg"
fi
echo "[2] Checking database directory: $DB_DIR"
if [ -d "$DB_DIR" ]; then
    DB_COUNT=$(find "$DB_DIR" -maxdepth 1 -name '*.db' -type f 2>/dev/null | wc -l)
    echo "  Found $DB_COUNT .db files"
    if [ "$DB_COUNT" -eq 0 ]; then
        echo "  WARNING: No .db files found. WeChat may not have been fully initialized."
    fi
else
    echo "  WARNING: db_storage/Msg directory does not exist yet."
    echo "  This is expected if WeChat hasn't been launched. Will create config anyway."
    mkdir -p "$DB_DIR"
fi

# --- Step 3: Generate wx-cli config.json ---
echo "[3] Generating wx-cli config..."
mkdir -p "$WX_CONFIG_DIR"

cat > "$WX_CONFIG_DIR/config.json" <<JSONEOF
{
  "db_dir": "$DB_DIR",
  "keys_file": "all_keys.json",
  "decrypted_dir": "cache",
  "wechat_process": "wechat"
}
JSONEOF

echo "  Config written to $WX_CONFIG_DIR/config.json"

# --- Step 4: Symlink to ~/.wx-cli if needed ---
echo "[4] Setting up wx-cli home directory symlink..."
if [ ! -L "$WX_CLI_HOME" ] && [ ! -d "$WX_CLI_HOME" ]; then
    ln -sf "$WX_CONFIG_DIR" "$WX_CLI_HOME"
    echo "  Symlink created: $WX_CLI_HOME -> $WX_CONFIG_DIR"
elif [ -L "$WX_CLI_HOME" ]; then
    echo "  Symlink already exists: $WX_CLI_HOME -> $(readlink -f "$WX_CLI_HOME")"
else
    echo "  ~/.wx-cli already exists as a directory, skipping symlink"
fi

# --- Step 5: Print summary ---
echo ""
echo "=== Config Alignment Complete ==="
echo "  WXID:        $WXID"
echo "  DB Dir:      $DB_DIR"
echo "  Config:      $WX_CONFIG_DIR/config.json"
echo "  Config Dir:  $(cat "$WX_CONFIG_DIR/config.json")"
