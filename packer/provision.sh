#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "ERROR: .env file not found." >&2
  exit 1
fi

set -a
source "$SCRIPT_DIR/.env"
set +a

SERVER_IP="${1:-${SERVER_IP:-}}"
: "${SERVER_IP:?Usage: $0 <server-ip>}"

SSH_USER="${SSH_USER:-root}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

ssh_run() {
  ssh $SSH_OPTS "${SSH_USER}@${SERVER_IP}" "$@"
}

echo "==> Removing ${SERVER_IP} from known_hosts..."
ssh-keygen -R "${SERVER_IP}" 2>/dev/null || true

echo "==> Connecting to ${SSH_USER}@${SERVER_IP}..."

echo "==> Running OpenClaw onboarding..."
ssh_run "bash /usr/local/bin/openclaw-onboard.sh"

echo ""
echo "==> Done. OpenClaw is ready on ${SERVER_IP}."
