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

# Onboard with Anthropic if key is set
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  openclaw onboard --non-interactive \
    --mode local \
    --auth-choice apiKey \
    --anthropic-api-key "$ANTHROPIC_API_KEY" \
    --gateway-port 18789 \
    --gateway-bind loopback \
    --install-daemon \
    --daemon-runtime node \
    --skip-skills
fi

# Onboard with Gemini if key is set
if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  openclaw onboard --non-interactive \
    --mode local \
    --auth-choice gemini-api-key \
    --gemini-api-key "$GEMINI_API_KEY" \
    --gateway-port 18789 \
    --gateway-bind loopback
fi

# Disable this service after successful first run
systemctl disable openclaw-setup.service
