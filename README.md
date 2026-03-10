# Cracker

Packer-based toolchain for building and deploying preconfigured [OpenClaw](https://openclaw.dev) servers on Hetzner Cloud.

## Overview

```
Build (Packer)          Deploy (deploy.sh)        First Boot
──────────────          ──────────────────        ──────────
ubuntu-24.04 image  →   Hetzner snapshot      →   openclaw onboard
+ Node.js               + secrets injected         (non-interactive)
+ openclaw npm          via cloud-init             daemon starts
+ systemd service                                  service disables itself
= snapshot saved
```

The snapshot contains no secrets. Secrets are injected at deploy time via cloud-init and consumed on first boot.

## Prerequisites

- [Packer](https://developer.hashicorp.com/packer/install) >= 1.9
- [hcloud CLI](https://github.com/hetznercloud/cli) (optional, for inspection)
- `curl`, `python3` (for `deploy.sh`)
- A Hetzner Cloud account and API token
- At least one of: Anthropic API key, Gemini API key

## 1. Configure environment

```bash
cp .env.example .env
```

Edit `.env` and fill in:

| Variable | Description |
|---|---|
| `PKR_VAR_hcloud_token` | Hetzner Cloud API token (used by Packer) |
| `HCLOUD_TOKEN` | Hetzner Cloud API token (used by deploy.sh) |
| `ANTHROPIC_API_KEY` | Anthropic API key (optional if Gemini is set) |
| `GEMINI_API_KEY` | Gemini API key (optional if Anthropic is set) |
| `OPENCLAW_GATEWAY_TOKEN` | OpenClaw gateway token |

At least one of `ANTHROPIC_API_KEY` or `GEMINI_API_KEY` must be set.

## 2. Install Packer plugin

```bash
packer init openclaw.pkr.hcl
```

## 3. Build the snapshot

```bash
./build.sh openclaw
```

Optionally pass SSH keys by Hetzner label selector so you can SSH into the build server for debugging:

```bash
./build.sh openclaw --ssh-keys-labels env=prod
```

This will:
1. Boot a temporary `cpx22` server in `hel1` from `ubuntu-24.04`
2. Run cloud-init (`cloud-init-openclaw.yaml`) — updates packages, installs base tools
3. Run `scripts/provision_openclaw.sh` — installs Node.js LTS, Neovim, clones Neovim config
4. Run `scripts/install_openclaw.sh` — installs `openclaw` npm package globally, installs `openclaw-setup.service` (disabled until deploy)
5. Save a Hetzner snapshot labelled `app=openclaw`
6. Destroy the temporary server

The snapshot is reusable. Rebuild only when you want to update the openclaw version or base configuration.

## 4. Deploy a server

```bash
./deploy.sh
```

All configuration is driven by environment variables. The script reads `.env` if present, but env vars already in the environment take precedence — making it safe to run from another OpenClaw instance.

### Environment variables for deploy

| Variable | Required | Default | Description |
|---|---|---|---|
| `HCLOUD_TOKEN` | yes | — | Hetzner API token |
| `ANTHROPIC_API_KEY` | one of | — | Anthropic API key |
| `GEMINI_API_KEY` | one of | — | Gemini API key |
| `OPENCLAW_GATEWAY_TOKEN` | yes | — | OpenClaw gateway token |
| `SERVER_NAME` | no | `openclaw-<timestamp>` | Server name |
| `SERVER_TYPE` | no | `cpx22` | Hetzner server type |
| `SERVER_LOCATION` | no | `hel1` | Hetzner location |
| `SSH_KEY_LABELS` | no | — | Hetzner label selector for SSH keys |
| `SSH_KEY_NAMES` | no | — | Comma-separated SSH key names |

### Examples

```bash
# Minimal — reads everything from .env
./deploy.sh

# Override server name and type
SERVER_NAME=openclaw-eu SERVER_TYPE=cpx32 ./deploy.sh

# Inject SSH keys by label
SSH_KEY_LABELS=env=prod ./deploy.sh

# Run from another OpenClaw instance (no .env needed)
HCLOUD_TOKEN=... ANTHROPIC_API_KEY=... OPENCLAW_GATEWAY_TOKEN=... ./deploy.sh
```

The script will:
1. Find the latest Hetzner snapshot labelled `app=openclaw`
2. Resolve SSH keys (if requested)
3. Build a cloud-init payload that writes `/root/openclaw.env` with your secrets (mode `0600`)
4. Create the server and print its name, ID, and public IP

## 5. First boot

Once the server starts, `openclaw-setup.service` runs automatically:

1. Sources `/root/openclaw.env` (written by cloud-init)
2. If `ANTHROPIC_API_KEY` is set, runs:
   ```
   openclaw onboard --non-interactive --mode local --auth-choice apiKey
     --gateway-port 18789 --gateway-bind loopback
     --install-daemon --daemon-runtime node --skip-skills
   ```
3. If `GEMINI_API_KEY` is set, runs:
   ```
   openclaw onboard --non-interactive --mode local --auth-choice gemini-api-key
     --gateway-port 18789 --gateway-bind loopback
   ```
4. Disables `openclaw-setup.service` so it never runs again

Monitor onboarding progress over SSH:

```bash
journalctl -u openclaw-setup.service -f
```

## Repository structure

```
.
├── build.sh                        # Build the Packer snapshot
├── deploy.sh                       # Deploy a server from the snapshot
├── openclaw.pkr.hcl                # Packer template for OpenClaw
├── ubuntu24.pkr.hcl                # Packer template for base dev image
├── cloud-init-openclaw.yaml        # Build-time cloud-init (base packages)
├── cloud-init-server-openclaw.yaml # Deploy-time cloud-init template (secrets)
├── scripts/
│   ├── provision_openclaw.sh       # Installs Node.js, Neovim, Neovim config
│   ├── install_openclaw.sh         # Installs openclaw npm + systemd service
│   ├── openclaw-start.sh           # First-boot onboarding script
│   └── cleanup.sh                  # Cleans up before snapshot
├── mcp/
│   └── setup.sh                    # Installs mcp-hetzner for MCP integration
├── .env.example                    # Environment variable template
└── .env                            # Local secrets (git-ignored)
```

## Rebuilding vs redeploying

| Scenario | Action |
|---|---|
| New openclaw npm version | Rebuild snapshot (`./build.sh openclaw`), redeploy |
| Different API keys / gateway token | Redeploy only (`./deploy.sh`) |
| Different server size or location | Redeploy only with `SERVER_TYPE` / `SERVER_LOCATION` |
| Base OS updates | Rebuild snapshot |
