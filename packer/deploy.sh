#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
  echo "ERROR: .env file not found. Copy .env.example and fill in the values." >&2
  exit 1
fi

set -a
source "$SCRIPT_DIR/.env"
set +a

# ---------------------------------------------------------------------------
# Validate
# ---------------------------------------------------------------------------
: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required in .env}"

if [[ -z "${ANTHROPIC_API_KEY:-}" && -z "${GEMINI_API_KEY:-}" ]]; then
  echo "ERROR: At least one of ANTHROPIC_API_KEY or GEMINI_API_KEY is required in .env." >&2
  exit 1
fi

if [[ -z "${SSH_KEY_NAMES:-}" && -z "${SSH_KEY_LABELS:-}" ]]; then
  echo "WARNING: No SSH keys specified (SSH_KEY_NAMES / SSH_KEY_LABELS). You will not be able to SSH into the server." >&2
fi

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
SERVER_NAME="${SERVER_NAME:-openclaw-$(date +%Y%m%d%H%M%S)}"
SERVER_TYPE="${SERVER_TYPE:-cpx22}"
SERVER_LOCATION="${SERVER_LOCATION:-hel1}"
VOLUME_IDS="${VOLUME_IDS:-}"
VOLUME_MOUNT="${VOLUME_MOUNT:-/mnt/data}"

hcloud_api() {
  curl -fsSL \
    -H "Authorization: Bearer ${HCLOUD_TOKEN}" \
    -H "Content-Type: application/json" \
    "$@"
}

# ---------------------------------------------------------------------------
# Resolve latest openclaw snapshot
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
# Resolve SSH keys
# ---------------------------------------------------------------------------
ssh_key_ids="[]"

if [[ -n "${SSH_KEY_NAMES:-}" ]]; then
  ssh_key_ids=$(python3 -c "
import json, sys
names = [n.strip() for n in sys.argv[1].split(',') if n.strip()]
print(json.dumps(names))
" "$SSH_KEY_NAMES")
  echo "==> Using SSH keys by name: ${ssh_key_ids}"

elif [[ -n "${SSH_KEY_LABELS:-}" ]]; then
  echo "==> Looking up SSH keys with label selector: ${SSH_KEY_LABELS}..."
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
# Resolve primary IPv4 (if set)
# ---------------------------------------------------------------------------
primary_ipv4_id=""

if [[ -n "${PRIMARY_IPV4_LABEL:-}" ]]; then
  echo "==> Looking up primary IP with label selector: ${PRIMARY_IPV4_LABEL}..."
  encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$PRIMARY_IPV4_LABEL")
  result=$(hcloud_api "https://api.hetzner.cloud/v1/primary_ips?label_selector=${encoded}&type=ipv4" | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
ips = data.get('primary_ips', [])
if not ips:
    print('ERROR: No primary IPv4 found with label selector: $PRIMARY_IPV4_LABEL', file=sys.stderr)
    sys.exit(1)
ip = ips[0]
print(ip['id'], ip['ip'], sep='|')
")
  primary_ipv4_ip="${result#*|}"
  primary_ipv4_id="${result%%|*}"
  echo "==> Using primary IP: ${primary_ipv4_ip} (ID: ${primary_ipv4_id})"

elif [[ -n "${PRIMARY_IPV4:-}" ]]; then
  echo "==> Looking up primary IP: ${PRIMARY_IPV4}..."
  encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$PRIMARY_IPV4")
  primary_ipv4_id=$(hcloud_api "https://api.hetzner.cloud/v1/primary_ips?ip=${encoded}" | \
    python3 -c "
import json, sys
data = json.load(sys.stdin)
ips = data.get('primary_ips', [])
if not ips:
    print('ERROR: Primary IP $PRIMARY_IPV4 not found in your Hetzner account.', file=sys.stderr)
    sys.exit(1)
print(ips[0]['id'])
")
  echo "==> Using primary IP ID: ${primary_ipv4_id}"
fi

# ---------------------------------------------------------------------------
# Detach volumes from any existing server
# ---------------------------------------------------------------------------
if [[ -n "$VOLUME_IDS" ]]; then
  for vol_id in ${VOLUME_IDS//,/ }; do
    attached_server=$(hcloud_api "https://api.hetzner.cloud/v1/volumes/${vol_id}" | \
      python3 -c "
import json, sys
data = json.load(sys.stdin)
server = data.get('volume', {}).get('server')
print(server if server else '')
")
    if [[ -n "$attached_server" ]]; then
      echo "==> Detaching volume ${vol_id} from server ${attached_server}..."
      hcloud_api -X POST "https://api.hetzner.cloud/v1/volumes/${vol_id}/actions/detach" -d '{}' > /dev/null
      sleep 2
    fi
  done
fi

# ---------------------------------------------------------------------------
# Build cloud-init user-data
# ---------------------------------------------------------------------------
user_data=$(envsubst < "$SCRIPT_DIR/cloud-init-server-openclaw.yaml")

# ---------------------------------------------------------------------------
# Create server
# ---------------------------------------------------------------------------
echo "==> Creating server '${SERVER_NAME}' (type: ${SERVER_TYPE}, location: ${SERVER_LOCATION})..."

volume_ids=$(python3 -c "
import json, sys
ids = [int(i.strip()) for i in sys.argv[1].split(',') if i.strip()]
print(json.dumps(ids))
" "$VOLUME_IDS")

payload=$(python3 -c "
import json, sys
data = {
    'name': sys.argv[1],
    'server_type': sys.argv[2],
    'location': sys.argv[3],
    'image': int(sys.argv[4]),
    'user_data': sys.argv[5],
    'ssh_keys': json.loads(sys.argv[6]),
    'labels': {'app': 'openclaw', 'managed': 'deploy'},
    'automount': False,
    'volumes': json.loads(sys.argv[8]),
}
primary_ipv4_id = sys.argv[7]
if primary_ipv4_id:
    data['public_net'] = {'ipv4': int(primary_ipv4_id), 'enable_ipv6': False}
print(json.dumps(data))
" "$SERVER_NAME" "$SERVER_TYPE" "$SERVER_LOCATION" "$snapshot_id" "$user_data" "$ssh_key_ids" "$primary_ipv4_id" "$volume_ids")

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
ipv4 = data['server']['public_net'].get('ipv4')
print(ipv4['ip'] if ipv4 else 'none')
")

echo ""
echo "==> Server created successfully!"
echo "    Name:      ${SERVER_NAME}"
echo "    ID:        ${server_id}"
echo "    Public IP: ${public_ip}"
echo ""
echo "    OpenClaw is being installed and onboarded via cloud-init."
echo "    Monitor with: tail -f /var/log/cloud-init-output.log"
