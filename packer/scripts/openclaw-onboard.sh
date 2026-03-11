#!/usr/bin/env bash
set -euo pipefail

set -a
source /root/openclaw.env
set +a

if [[ -n "$ANTHROPIC_API_KEY" ]]; then
  echo "==> Onboarding with Anthropic..."
  openclaw onboard --non-interactive \
    --accept-risk \
    --mode local \
    --auth-choice apiKey \
    --anthropic-api-key "$ANTHROPIC_API_KEY" \
    --gateway-port 18789 \
    --gateway-bind loopback \
    --gateway-auth token \
    --install-daemon \
    --daemon-runtime node \
    --skip-skills
fi

if [[ -n "$GEMINI_API_KEY" ]]; then
  echo "==> Onboarding with Gemini..."
  openclaw onboard --non-interactive \
    --accept-risk \
    --workspace "$OPENCLAW_WORKSPACE_DIR"
    --mode local \
    --auth-choice gemini-api-key \
    --gemini-api-key "$GEMINI_API_KEY" \
    --gateway-auth token \
    --gateway-port 18789 \
    --gateway-bind loopback \
    --install-daemon \
    --daemon-runtime node \
    --skip-skills
fi

echo "==> OpenClaw onboarding complete."
