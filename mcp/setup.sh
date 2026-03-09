#!/usr/bin/env bash
set -euo pipefail

# Install mcp-hetzner
pip install git+https://github.com/dkruyt/mcp-hetzner.git

echo "mcp-hetzner installed. Make sure HCLOUD_TOKEN is set in your .env"
