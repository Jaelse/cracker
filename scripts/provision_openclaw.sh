#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Update and upgrade
apt-get update
apt-get upgrade -y

# Install dependencies
apt-get install -y \
  curl \
  wget \
  ca-certificates \
  gnupg \
  git

# Install Node.js LTS
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs

# Install Neovim (latest stable via PPA)
add-apt-repository -y ppa:neovim-ppa/stable
apt-get update
apt-get install -y neovim

# Install Neovim config
git clone https://github.com/Jaelse/nvim /root/.config/nvim

# Disable root SSH password login
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

# Set timezone to UTC
timedatectl set-timezone UTC

bash /tmp/cleanup.sh
