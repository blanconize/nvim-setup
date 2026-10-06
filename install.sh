#!/usr/bin/env bash
#
# Installs these dotfiles on macOS or Linux (apt, dnf or pacman): CLI tooling,
# oh-my-zsh + theme, Claude Code, fonts/terminal where there is a GUI, Neovim
# plugins/LSPs, and symlinks for every config file (including ~/.claude).
# Nothing is pinned – every installer fetches the current version. Safe to
# re-run; existing real files are backed up as <file>.bak.

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# shellcheck source=install/lib.sh
source "$DOTFILES/install/lib.sh"

case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *)      die "Unsupported OS $(uname -s): this installer targets macOS and Linux." ;;
esac
# shellcheck source=/dev/null # install/macos.sh or install/linux.sh, both linted directly
source "$DOTFILES/install/$OS.sh"

install_shell() {
  info "Checking for oh-my-zsh..."
  if [ -d "$HOME/.oh-my-zsh" ]; then
    ok "  oh-my-zsh is already installed"
  else
    warn "  installing oh-my-zsh"
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  fi

  info "Checking for honukai theme..."
  if [ -f "$ZSH_CUSTOM/themes/honukai.zsh-theme" ]; then
    ok "  honukai theme is already installed"
  else
    warn "  installing honukai theme"
    curl -fsSL --create-dirs -o "$ZSH_CUSTOM/themes/honukai.zsh-theme" \
      https://raw.githubusercontent.com/oskarkrawczyk/honukai-iterm/master/honukai.zsh-theme
  fi
  set_zsh_theme honukai
}

install_claude() {
  info "Checking for Claude Code..."
  export PATH="$HOME/.local/bin:$PATH"
  if command -v claude >/dev/null 2>&1; then
    ok "  Claude Code $(claude --version 2>/dev/null | head -1) is already installed"
  else
    warn "  installing Claude Code (native installer -> ~/.local/bin)"
    curl -fsSL https://claude.ai/install.sh | bash
  fi
}

link_configs() {
  info "Linking config files..."
  link .gitconfig        "$HOME/.gitconfig"
  link .gitconfig-aviam  "$HOME/.gitconfig-aviam"
  link ".gitconfig-$OS"  "$HOME/.gitconfig-os"
  link .gitignore_global "$HOME/.gitignore_global"
  link .zsh-aliases      "$HOME/.zsh-aliases"
  link .zsh-tools        "$HOME/.zsh-tools"
  link .tmux.conf        "$HOME/.tmux.conf"
  link nvim              "$HOME/.config/nvim"

  info "Linking Claude Code config..."
  mkdir -p "$HOME/.claude"
  link claude/CLAUDE.md      "$HOME/.claude/CLAUDE.md"
  link claude/settings.json  "$HOME/.claude/settings.json"
  link claude/hooks          "$HOME/.claude/hooks"

  info "Wiring shell files into ~/.zshrc..."
  ensure_line "$HOME/.zshrc" 'zsh-aliases' 'source ~/.zsh-aliases'
  ensure_line "$HOME/.zshrc" 'zsh-tools'   'source ~/.zsh-tools'
}

install_nvim_tooling() {
  local pkg missing=""
  info "Installing Neovim plugins, parsers and language servers..."
  nvim --headless "+Lazy! sync" +qa
  nvim --headless -c 'lua require("nvim-treesitter").install(vim.g.ts_langs):wait(600000)' +qa
  for pkg in $MASON_PKGS; do
    [ -d "$HOME/.local/share/nvim/mason/packages/$pkg" ] || missing="$missing $pkg"
  done
  if [ -n "$missing" ]; then
    nvim --headless -c "MasonInstall$missing" +qa
  else
    ok "  all Mason packages already installed"
  fi
  ok "  done"
}

platform_preflight
platform_packages
install_shell
install_claude
platform_gui
link_configs
install_nvim_tooling
platform_finish
