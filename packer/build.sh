#!/usr/bin/env bash
set -euo pipefail

TEMPLATE=""
SSH_KEY_LABELS=""

usage() {
  echo "Usage: $0 [dev|openclaw] [--ssh-keys-labels <label-selector>]" >&2
  echo "  e.g. $0 dev --ssh-keys-labels env=prod" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    dev|openclaw)
      TEMPLATE="$1"
      shift
      ;;
    --ssh-keys-labels)
      [[ -z "${2:-}" ]] && usage
      SSH_KEY_LABELS="$2"
      shift 2
      ;;
    *)
      usage
      ;;
  esac
done

if [[ ! -f .env ]]; then
  echo "ERROR: .env file not found. Copy .env.example and fill in the values." >&2
  exit 1
fi

set -a
source .env
set +a

PACKER_ARGS=()

if [[ -n "$SSH_KEY_LABELS" ]]; then
  echo "==> Looking up SSH keys with label selector: ${SSH_KEY_LABELS}"

  response=$(curl -fsSL \
    -H "Authorization: Bearer ${PKR_VAR_hcloud_token}" \
    "https://api.hetzner.cloud/v1/ssh_keys?label_selector=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$SSH_KEY_LABELS")")

  key_names=$(echo "$response" | python3 -c "
import json, sys
data = json.load(sys.stdin)
keys = [k['name'] for k in data.get('ssh_keys', [])]
if not keys:
    print('ERROR: No SSH keys found matching label selector', file=sys.stderr)
    sys.exit(1)
print(json.dumps(keys))
")

  echo "==> Found SSH keys: ${key_names}"
  PACKER_ARGS+=(-var "ssh_key_names=${key_names}")
fi

case "$TEMPLATE" in
  openclaw)
    packer build "${PACKER_ARGS[@]}" openclaw.pkr.hcl
    ;;
  dev|"")
    packer build "${PACKER_ARGS[@]}" ubuntu24.pkr.hcl
    ;;
esac
