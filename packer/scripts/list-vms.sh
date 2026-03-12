#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/../.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: .env file not found." >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

: "${HCLOUD_TOKEN:?HCLOUD_TOKEN is required in .env}"

echo "==> Fetching VMs labelled app=openclaw..."
echo ""

curl -fsSL \
  -H "Authorization: Bearer ${HCLOUD_TOKEN}" \
  "https://api.hetzner.cloud/v1/servers?label_selector=app%3Dopenclaw" | \
  python3 -c "
import json, sys
from datetime import datetime

data = json.load(sys.stdin)
servers = data.get('servers', [])

if not servers:
    print('No VMs found.')
    sys.exit(0)

fmt = '{:<30} {:<12} {:<16} {:<12} {:<10} {}'
print(fmt.format('NAME', 'STATUS', 'PUBLIC IP', 'TYPE', 'LOCATION', 'CREATED'))
print('-' * 100)

for s in servers:
    name     = s['name']
    status   = s['status']
    ipv4     = s['public_net']['ipv4']['ip'] if s['public_net'].get('ipv4') else 'none'
    stype    = s['server_type']['name']
    location = s['datacenter']['location']['name']
    created  = s['created'][:19].replace('T', ' ')
    print(fmt.format(name, status, ipv4, stype, location, created))

print()
print(f'Total: {len(servers)} VM(s)')
"
