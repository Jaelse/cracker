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

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
SERVER_IP="${1:-${SERVER_IP:-}}"
: "${SERVER_IP:?Usage: $0 <server-ip>}"

SSH_USER="${SSH_USER:-root}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"

# ---------------------------------------------------------------------------
# Validate auth
# ---------------------------------------------------------------------------
if [[ -z "${ANTHROPIC_API_KEY:-}" && -z "${GEMINI_API_KEY:-}" ]]; then
  echo "ERROR: At least one of ANTHROPIC_API_KEY or GEMINI_API_KEY is required in .env." >&2
  exit 1
fi

echo "==> Setting up OpenClaw on ${SSH_USER}@${SERVER_IP}..."

# ---------------------------------------------------------------------------
# Write env file on the server
# ---------------------------------------------------------------------------
echo "==> Uploading openclaw.env..."
ssh $SSH_OPTS "${SSH_USER}@${SERVER_IP}" "cat > /root/openclaw.env && chmod 600 /root/openclaw.env" <<ENV
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}
GEMINI_API_KEY=${GEMINI_API_KEY:-}
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN:-}
OPENCLAW_GATEWAY_BIND=${OPENCLAW_GATEWAY_BIND:-lan}
OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT:-18789}
OPENCLAW_BRIDGE_PORT=${OPENCLAW_BRIDGE_PORT:-18790}
OPENCLAW_CONFIG_DIR=${OPENCLAW_CONFIG_DIR:-/root/.openclaw}
OPENCLAW_WORKSPACE_DIR=${OPENCLAW_WORKSPACE_DIR:-/root/.openclaw/workspace}
OPENCLAW_SANDBOX=${OPENCLAW_SANDBOX:-}
OPENCLAW_DOCKER_SOCKET=${OPENCLAW_DOCKER_SOCKET:-/var/run/docker.sock}
OPENCLAW_HOME_VOLUME=${OPENCLAW_HOME_VOLUME:-}
OPENCLAW_EXTRA_MOUNTS=${OPENCLAW_EXTRA_MOUNTS:-}
OPENCLAW_DOCKER_APT_PACKAGES=${OPENCLAW_DOCKER_APT_PACKAGES:-}
OPENCLAW_EXTENSIONS=${OPENCLAW_EXTENSIONS:-}
OPENCLAW_INSTALL_DOCKER_CLI=${OPENCLAW_INSTALL_DOCKER_CLI:-}
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=${OPENCLAW_ALLOW_INSECURE_PRIVATE_WS:-}
ENV

# ---------------------------------------------------------------------------
# Run onboarding
# ---------------------------------------------------------------------------
echo "==> Running OpenClaw onboarding..."

ssh $SSH_OPTS "${SSH_USER}@${SERVER_IP}" bash <<'REMOTE'
set -euo pipefail

set -a
source /root/openclaw.env
set +a

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "--> Onboarding with Anthropic..."
  openclaw onboard --non-interactive \
    --accept-risk \
    --mode local \
    --auth-choice apiKey \
    --anthropic-api-key "$ANTHROPIC_API_KEY" \
    --gateway-port 18789 \
    --gateway-bind loopback \
    --install-daemon \
    --daemon-runtime node \
    --skip-skills
fi

if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  echo "--> Onboarding with Gemini..."
  openclaw onboard --non-interactive \
    --accept-risk \
    --mode local \
    --auth-choice gemini-api-key \
    --gemini-api-key "$GEMINI_API_KEY" \
    --gateway-port 18789 \
    --gateway-bind loopback
fi
REMOTE

echo ""
echo "==> OpenClaw setup complete on ${SERVER_IP}."
