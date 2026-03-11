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
SERVER_NAME="${1:-${SERVER_NAME:-}}"
: "${SERVER_NAME:?Usage: $0 <server-name>}"
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required in .env}"

hcloud_api() {
  curl -fsSL \
    -H "Authorization: Bearer ${HCLOUD_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

# ---------------------------------------------------------------------------
# Resolve server ID
# ---------------------------------------------------------------------------
echo "==> Looking up server '${SERVER_NAME}'..."
encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$SERVER_NAME")
server=$(hcloud_api "https://api.hetzner.cloud/v1/servers?name=${encoded}" | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
servers = data.get('servers', [])
if not servers:
    print('ERROR: Server not found: $SERVER_NAME', file=sys.stderr)
    sys.exit(1)
s = servers[0]
print(s['id'], s['status'], sep='|')
")
server_id="${server%%|*}"
server_status="${server#*|}"
echo "==> Found server ID: ${server_id} (status: ${server_status})"

# ---------------------------------------------------------------------------
# Detach volumes
# ---------------------------------------------------------------------------
echo "==> Checking for attached volumes..."
volumes=$(hcloud_api "https://api.hetzner.cloud/v1/volumes?server=${server_id}" | \
  python3 -c "
import json, sys
data = json.load(sys.stdin)
print(' '.join(str(v['id']) for v in data.get('volumes', [])))
")

if [[ -n "$volumes" ]]; then
  for vol_id in $volumes; do
    echo "==> Detaching volume ${vol_id}..."
    hcloud_api -X POST "https://api.hetzner.cloud/v1/volumes/${vol_id}/actions/detach" -d '{}' > /dev/null
  done
  echo "==> Waiting for volumes to detach..."
  sleep 3
else
  echo "==> No volumes attached."
fi

# ---------------------------------------------------------------------------
# Power off
# ---------------------------------------------------------------------------
if [[ "$server_status" != "off" ]]; then
  echo "==> Powering off server..."
  hcloud_api -X POST "https://api.hetzner.cloud/v1/servers/${server_id}/actions/poweroff" -d '{}' > /dev/null

  echo "==> Waiting for server to power off..."
  while true; do
    status=$(hcloud_api "https://api.hetzner.cloud/v1/servers/${server_id}" | \
      python3 -c "import json,sys; print(json.load(sys.stdin)['server']['status'])")
    [[ "$status" == "off" ]] && break
    sleep 2
  done
  echo "==> Server is off."
else
  echo "==> Server is already off."
fi

# ---------------------------------------------------------------------------
# Delete server
# ---------------------------------------------------------------------------
echo "==> Deleting server '${SERVER_NAME}'..."
hcloud_api -X DELETE "https://api.hetzner.cloud/v1/servers/${server_id}" > /dev/null
echo ""
echo "==> Server '${SERVER_NAME}' deleted."
