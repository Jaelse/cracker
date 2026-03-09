#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Update and upgrade
apt-get update
apt-get upgrade -y

# Install common tools
apt-get install -y \
  curl \
  wget \
  unzip \
  ca-certificates \
  gnupg \
  git \
  zsh \
  tmux

# Install Neovim (latest stable via PPA)
add-apt-repository -y ppa:neovim-ppa/stable
apt-get update
apt-get install -y neovim

# Install Neovim config
git clone https://github.com/Jaelse/nvim /root/.config/nvim

# Install JetBrainsMono Nerd Font
FONT_VERSION=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | grep '"tag_name"' | cut -d'"' -f4)
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${FONT_VERSION}/JetBrainsMono.tar.xz" \
  -o /tmp/JetBrainsMono.tar.xz
mkdir -p /usr/local/share/fonts/JetBrainsMonoNerdFont
tar -xf /tmp/JetBrainsMono.tar.xz -C /usr/local/share/fonts/JetBrainsMonoNerdFont
fc-cache -fv
rm /tmp/JetBrainsMono.tar.xz

# Install Docker
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Install GitHub CLI
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
  | tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-get update
apt-get install -y gh

# Install Claude Code (requires Node.js)
curl -fsSL https://deb.nodesource.com/setup_lts.x | bash -
apt-get install -y nodejs
npm install -g @anthropic-ai/claude-code

# Install zinit
bash -c "$(curl -fsSL https://raw.githubusercontent.com/zdharma-continuum/zinit/HEAD/scripts/install.sh)" -- --no-input

# Write .zshrc with zinit + powerlevel10k
cat > /root/.zshrc <<'EOF'
# Enable Powerlevel10k instant prompt (must be at top of .zshrc)
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Zinit
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"
source "${ZINIT_HOME}/zinit.zsh"
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# Powerlevel10k theme
zinit ice depth=1; zinit light romkatv/powerlevel10k

# Plugins
zinit light zsh-users/zsh-autosuggestions
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions

# History
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history
setopt hist_ignore_dups
setopt share_history

# Completion
autoload -Uz compinit && compinit

# Neovim as default editor
export EDITOR=nvim
export VISUAL=nvim
alias vi=nvim
alias vim=nvim

# Load p10k config if it exists
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
EOF

# Set zsh as default shell for root
chsh -s "$(which zsh)" root

# Disable root SSH password login
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config

# Set timezone to UTC
timedatectl set-timezone UTC

bash /tmp/cleanup.sh
