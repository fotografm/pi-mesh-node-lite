#!/bin/bash
# setup-pi-3.sh  —  raspi30 systemd service files
# Run on the Pi AFTER setup-pi-2.sh and second reboot.
# Installs and enables five services. Does NOT start them yet —
# run setup-deploy.sh from your desktop after this to push scripts and binaries,
# then all services will start automatically.
#
# Port map:
#   :8080 HTTP   sdr-ws         SDR waterfall page    (Rust binary)
#   :8081 WS     sdr-ws         SDR spectrum frames   (Rust binary)
#   :8082 WS     meshtastic-ws  RAK4631 bridge        (Python)
#   :8083 WS     meshcore-ws    Heltec V3 bridge      (Python)
#   :8084 WS     terminal-ws    xterm.js PTY          (Python)
#   :8090 HTTP   quad-server    Four-quadrant page    (Python)
set -e

echo "==================================================================="
echo " raspi30  setup-pi-3.sh"
echo "==================================================================="

SYSTEMD=/etc/systemd/system

# ---------------------------------------------------------------------------
# Helper — write a service file and enable it (idempotent)
# ---------------------------------------------------------------------------
install_service() {
    local NAME=$1
    local FILE="$SYSTEMD/$NAME"
    echo "      $NAME"
    sudo systemctl stop "$NAME" 2>/dev/null || true
    sudo cp "/tmp/$NAME" "$FILE"
    sudo systemctl daemon-reload
    sudo systemctl enable "$NAME"
}

# ---------------------------------------------------------------------------
# [1/6]  sdr-ws.service  (Rust binary, deployed by setup-deploy.sh)
# ---------------------------------------------------------------------------
echo ""
echo "[1/6] sdr-ws.service..."
cat > /tmp/sdr-ws.service << 'EOF'
[Unit]
Description=SDR WebSocket Spectrum Server
After=network.target

[Service]
Type=simple
User=user
WorkingDirectory=/home/user
ExecStart=/home/user/sdr-ws
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
install_service sdr-ws.service

# ---------------------------------------------------------------------------
# [2/6]  meshtastic-ws.service  (RAK4631 bridge)
# ---------------------------------------------------------------------------
echo ""
echo "[2/6] meshtastic-ws.service..."
cat > /tmp/meshtastic-ws.service << 'EOF'
[Unit]
Description=Meshtastic WebSocket Bridge (RAK4631)
After=network.target

[Service]
Type=simple
User=user
WorkingDirectory=/home/user/raspi30
ExecStart=/home/user/meshtastic-venv/bin/python /home/user/raspi30/meshtastic-ws.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
install_service meshtastic-ws.service

# ---------------------------------------------------------------------------
# [3/6]  meshcore-ws.service  (Heltec V3 bridge)
# ---------------------------------------------------------------------------
echo ""
echo "[3/6] meshcore-ws.service..."
cat > /tmp/meshcore-ws.service << 'EOF'
[Unit]
Description=MeshCore WebSocket Bridge (Heltec V3)
After=network.target

[Service]
Type=simple
User=user
WorkingDirectory=/home/user/raspi30
ExecStart=/home/user/meshcore-venv/bin/python /home/user/raspi30/meshcore-ws.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
install_service meshcore-ws.service

# ---------------------------------------------------------------------------
# [4/6]  terminal-ws.service  (PTY xterm.js bridge)
# ---------------------------------------------------------------------------
echo ""
echo "[4/6] terminal-ws.service..."
cat > /tmp/terminal-ws.service << 'EOF'
[Unit]
Description=Terminal WebSocket PTY Bridge
After=network.target

[Service]
Type=simple
User=user
WorkingDirectory=/home/user
ExecStart=/home/user/raspi30-venv/bin/python /home/user/raspi30/terminal-ws.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
install_service terminal-ws.service

# ---------------------------------------------------------------------------
# [5/6]  quad-server.service  (serves quad-index.html on :8090)
# ---------------------------------------------------------------------------
echo ""
echo "[5/6] quad-server.service..."
cat > /tmp/quad-server.service << 'EOF'
[Unit]
Description=Quad-panel HTTP Server
After=network.target

[Service]
Type=simple
User=user
WorkingDirectory=/home/user/raspi30
ExecStart=/home/user/raspi30-venv/bin/python /home/user/raspi30/quad-server.py
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
install_service quad-server.service

# ---------------------------------------------------------------------------
# [6/6]  Verify all enabled
# ---------------------------------------------------------------------------
echo ""
echo "[6/6] Verifying enabled services..."
for SVC in sdr-ws meshtastic-ws meshcore-ws terminal-ws quad-server; do
    STATE=$(systemctl is-enabled ${SVC}.service 2>/dev/null || echo "unknown")
    printf "      %-20s %s\n" "${SVC}.service" "$STATE"
done

echo ""
echo "==================================================================="
echo " setup-pi-3.sh COMPLETE"
echo "==================================================================="
echo ""
echo "  All services are ENABLED but NOT yet started."
echo "  Scripts and binary must be deployed first."
echo ""
echo "  From your desktop, run setup-deploy.sh to:"
echo "    - Cross-compile and deploy the sdr-ws Rust binary"
echo "    - Deploy meshtastic-ws.py, meshcore-ws.py"
echo "    - Deploy terminal-ws.py, quad-server.py, quad-index.html"
echo "    - Start all five services"
echo ""
echo "  URLs once deployed (connect to raspi30 hotspot first):"
echo "    http://10.42.0.1:8080   SDR waterfall"
echo "    http://10.42.0.1:8090   Four-quadrant page"
echo ""
echo "  No reboot needed — setup-deploy.sh starts everything directly."
