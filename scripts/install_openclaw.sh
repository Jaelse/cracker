#!/usr/bin/env bash
set -euo pipefail

# Install OpenClaw globally via npm (skip onboarding — done at first boot)
npm install -g openclaw@latest

# Install startup script
cp /tmp/openclaw-start.sh /usr/local/bin/openclaw-start.sh
chmod +x /usr/local/bin/openclaw-start.sh

# Install systemd service
cat > /etc/systemd/system/openclaw-setup.service <<'EOF'
[Unit]
Description=OpenClaw first-boot setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/openclaw-start.sh
RemainAfterExit=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable openclaw-setup.service
