#!/usr/bin/env bash
set -euo pipefail

ENV_SOURCE="/root/openclaw.env"

if [[ ! -f "$ENV_SOURCE" ]]; then
  echo "ERROR: $ENV_SOURCE not found. Place your .env file there and reboot or re-run." >&2
  exit 1
fi

set -a
source "$ENV_SOURCE"
set +a

# Onboard and install the gateway daemon
openclaw onboard --install-daemon

# Disable this service after successful first run
systemctl disable openclaw-setup.service
