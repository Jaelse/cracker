#!/usr/bin/env bash
set -euo pipefail

set -a
source /root/openclaw.env
set +a


npm install -g openclaw@latest

# Install bash completion
openclaw completion -i -s bash -y --write-state

npm install clawhub@latest 
