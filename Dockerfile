FROM nickrunning/wechat-selkies:latest

# ============================================================
# Pre-install dependencies that would otherwise be lost on rebuild
# ============================================================

ARG DEBIAN_FRONTEND=noninteractive

# System packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    gdb=15.1-1ubuntu1~24.04.1 \
    python3-pip=24.0+dfsg-1ubuntu1.3 \
    sqlcipher=4.5.6-1build2 \
    wget=1.21.4-1ubuntu4.1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Python packages
RUN pip3 install --no-cache-dir --break-system-packages \
    sqlcipher3==0.6.2 \
    pycryptodome==3.23.0

# wx-cli binary
RUN wget -q -O /usr/local/bin/wx-cli \
    "https://github.com/jackwener/wx-cli/releases/download/v0.1.10/wx-linux-x86_64" \
    && chmod +x /usr/local/bin/wx-cli

# wcdb-key-tool source
RUN git clone --depth 1 \
    https://github.com/bjdr69/wcdb-key-tool.git /opt/wcdb-key-tool \
    && chmod +x /opt/wcdb-key-tool/wcdb_key_tool.py

# Cont-init script: sync tools to /config/tools on every container start
# LinuxServer.io s6-overlay executes scripts in /custom-cont-init.d/ at boot
COPY docker-entrypoint.sh /custom-cont-init.d/99-wxcli-init
RUN chmod +x /custom-cont-init.d/99-wxcli-init
