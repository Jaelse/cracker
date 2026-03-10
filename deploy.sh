#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load .env if present (local use). Env vars already in the environment take precedence.
if [[ -f "$SCRIPT_DIR/.env" ]]; then
  while IFS= read -r line; do
    [[ "$line" =~ ^#|^$ ]] && continue
    key="${line%%=*}"
    [[ -v "$key" ]] || export "$line"
  done < "$SCRIPT_DIR/.env"
fi

# ---------------------------------------------------------------------------
# Required
# ---------------------------------------------------------------------------
HCLOUD_TOKEN="${HCLOUD_TOKEN:-${PKR_VAR_hcloud_token:-}}"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"
GEMINI_API_KEY="${GEMINI_API_KEY:-}"
if [[ -z "$ANTHROPIC_API_KEY" && -z "$GEMINI_API_KEY" ]]; then
  echo "ERROR: At least one of ANTHROPIC_API_KEY or GEMINI_API_KEY is required." >&2
  exit 1
fi
: "${OPENCLAW_GATEWAY_TOKEN:?OPENCLAW_GATEWAY_TOKEN is required}"

# ---------------------------------------------------------------------------
# Optional with defaults
# ---------------------------------------------------------------------------
SERVER_NAME="${SERVER_NAME:-openclaw-$(date +%Y%m%d%H%M%S)}"
SERVER_TYPE="${SERVER_TYPE:-${PKR_VAR_server_type:-cpx22}}"
SERVER_LOCATION="${SERVER_LOCATION:-${PKR_VAR_location:-hel1}}"
SSH_KEY_LABELS="${SSH_KEY_LABELS:-}"       # Hetzner label selector, e.g. env=prod
SSH_KEY_NAMES="${SSH_KEY_NAMES:-}"         # Comma-separated key names (overrides labels)

# OpenClaw env vars for the deployed server
OPENCLAW_GATEWAY_BIND="${OPENCLAW_GATEWAY_BIND:-lan}"
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
OPENCLAW_BRIDGE_PORT="${OPENCLAW_BRIDGE_PORT:-18790}"
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-/root/.openclaw}"
OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/root/.openclaw/workspace}"
OPENCLAW_SANDBOX="${OPENCLAW_SANDBOX:-}"
OPENCLAW_DOCKER_SOCKET="${OPENCLAW_DOCKER_SOCKET:-/var/run/docker.sock}"
OPENCLAW_HOME_VOLUME="${OPENCLAW_HOME_VOLUME:-}"
OPENCLAW_EXTRA_MOUNTS="${OPENCLAW_EXTRA_MOUNTS:-}"
OPENCLAW_DOCKER_APT_PACKAGES="${OPENCLAW_DOCKER_APT_PACKAGES:-}"
OPENCLAW_EXTENSIONS="${OPENCLAW_EXTENSIONS:-}"
OPENCLAW_INSTALL_DOCKER_CLI="${OPENCLAW_INSTALL_DOCKER_CLI:-}"
OPENCLAW_ALLOW_INSECURE_PRIVATE_WS="${OPENCLAW_ALLOW_INSECURE_PRIVATE_WS:-}"

hcloud_api() {
  curl -fsSL \
    -H "Authorization: Bearer ${HCLOUD_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

# ---------------------------------------------------------------------------
# Resolve latest openclaw snapshot ID
# ---------------------------------------------------------------------------
echo "==> Looking up latest openclaw snapshot..."
snapshot_id=$(hcloud_api "https://api.hetzner.cloud/v1/images?type=snapshot&label_selector=app%3Dopenclaw&sort=created:desc" | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
images = data.get('images', [])
if not images:
    print('ERROR: No openclaw snapshot found. Run ./build.sh openclaw first.', file=sys.stderr)
    sys.exit(1)
print(images[0]['id'])
")
echo "==> Using snapshot ID: ${snapshot_id}"

# ---------------------------------------------------------------------------
# Resolve SSH key IDs
# ---------------------------------------------------------------------------
ssh_key_ids="[]"

if [[ -n "$SSH_KEY_NAMES" ]]; then
  ssh_key_ids=$(python3 -c "
import json, sys
names = [n.strip() for n in sys.argv[1].split(',') if n.strip()]
print(json.dumps(names))
" "$SSH_KEY_NAMES")
  echo "==> Using SSH keys by name: ${ssh_key_ids}"

elif [[ -n "$SSH_KEY_LABELS" ]]; then
  echo "==> Looking up SSH keys with label selector: ${SSH_KEY_LABELS}"
  encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$SSH_KEY_LABELS")
  ssh_key_ids=$(hcloud_api "https://api.hetzner.cloud/v1/ssh_keys?label_selector=${encoded}" | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
keys = [k['name'] for k in data.get('ssh_keys', [])]
if not keys:
    print('ERROR: No SSH keys found for label selector.', file=sys.stderr)
    sys.exit(1)
print(json.dumps(keys))
")
  echo "==> Found SSH keys: ${ssh_key_ids}"
fi

# ---------------------------------------------------------------------------
# Build cloud-init user-data
# ---------------------------------------------------------------------------
user_data=$(cat <<YAML
#cloud-config
write_files:
  - path: /root/openclaw.env
    owner: root:root
    permissions: "0600"
    content: |
      ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
      GEMINI_API_KEY=${GEMINI_API_KEY}
      OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
      OPENCLAW_GATEWAY_BIND=${OPENCLAW_GATEWAY_BIND}
      OPENCLAW_GATEWAY_PORT=${OPENCLAW_GATEWAY_PORT}
      OPENCLAW_BRIDGE_PORT=${OPENCLAW_BRIDGE_PORT}
      OPENCLAW_CONFIG_DIR=${OPENCLAW_CONFIG_DIR}
      OPENCLAW_WORKSPACE_DIR=${OPENCLAW_WORKSPACE_DIR}
      OPENCLAW_SANDBOX=${OPENCLAW_SANDBOX}
      OPENCLAW_DOCKER_SOCKET=${OPENCLAW_DOCKER_SOCKET}
      OPENCLAW_HOME_VOLUME=${OPENCLAW_HOME_VOLUME}
      OPENCLAW_EXTRA_MOUNTS=${OPENCLAW_EXTRA_MOUNTS}
      OPENCLAW_DOCKER_APT_PACKAGES=${OPENCLAW_DOCKER_APT_PACKAGES}
      OPENCLAW_EXTENSIONS=${OPENCLAW_EXTENSIONS}
      OPENCLAW_INSTALL_DOCKER_CLI=${OPENCLAW_INSTALL_DOCKER_CLI}
      OPENCLAW_ALLOW_INSECURE_PRIVATE_WS=${OPENCLAW_ALLOW_INSECURE_PRIVATE_WS}
YAML
)

# ---------------------------------------------------------------------------
# Create server
# ---------------------------------------------------------------------------
echo "==> Creating server '${SERVER_NAME}' (type: ${SERVER_TYPE}, location: ${SERVER_LOCATION})..."

payload=$(python3 -c "
import json, sys
data = {
    'name': sys.argv[1],
    'server_type': sys.argv[2],
    'location': sys.argv[3],
    'image': int(sys.argv[4]),
    'user_data': sys.argv[5],
    'ssh_keys': json.loads(sys.argv[6]),
    'labels': {'app': 'openclaw', 'managed': 'deploy'}
}
print(json.dumps(data))
" "$SERVER_NAME" "$SERVER_TYPE" "$SERVER_LOCATION" "$snapshot_id" "$user_data" "$ssh_key_ids")

response=$(hcloud_api -X POST "https://api.hetzner.cloud/v1/servers" -d "$payload")

server_id=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
if 'error' in data:
    print('ERROR:', data['error'].get('message', data['error']), file=sys.stderr)
    sys.exit(1)
print(data['server']['id'])
")

public_ip=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print(data['server']['public_net']['ipv4']['ip'])
")

echo ""
echo "==> Server created successfully!"
echo "    Name:      ${SERVER_NAME}"
echo "    ID:        ${server_id}"
echo "    Public IP: ${public_ip}"
echo ""
echo "    OpenClaw will onboard automatically on first boot."
echo "    Monitor with: journalctl -u openclaw-setup.service -f"
