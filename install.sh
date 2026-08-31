#!/usr/bin/env bash
#
# Installs these dotfiles on macOS: tooling via Homebrew, oh-my-zsh + theme,
# and symlinks for the config files. Safe to re-run; existing real files are
# backed up as <file>.bak before being replaced by a symlink.

set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

info()  { printf '\033[36m%s\033[0m\n' "$1"; }
ok()    { printf '\033[32m%s\033[0m\n' "$1"; }
warn()  { printf '\033[31m%s\033[0m\n' "$1"; }

need_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    warn "Homebrew is required to install $1 – see https://brew.sh"
    exit 1
  fi
}

ensure_tool() { # ensure_tool <binary> <brew formula>
  info "Checking for $1..."
  if command -v "$1" >/dev/null 2>&1; then
    ok "  $1 is already installed"
  else
    warn "  installing $1"
    need_brew "$1"
    brew install "$2"
  fi
}

link() { # link <repo file> <target>
  local src="$DOTFILES/$1" dst="$2"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    ok "  $dst already linked"
    return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    warn "  backing up $dst -> $dst.bak"
    mv "$dst" "$dst.bak"
  fi
  ln -s "$src" "$dst"
  ok "  linked $dst -> $src"
}

ensure_tool zsh zsh
ensure_tool rg ripgrep
ensure_tool fzf fzf

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

info "Checking for vim-plug..."
if [ -f "$HOME/.vim/autoload/plug.vim" ]; then
  ok "  vim-plug is already installed"
else
  warn "  installing vim-plug"
  curl -fsSL --create-dirs -o "$HOME/.vim/autoload/plug.vim" \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
fi

info "Linking config files..."
link .vimrc            "$HOME/.vimrc"
link .gitconfig        "$HOME/.gitconfig"
link .gitignore_global "$HOME/.gitignore_global"
link .zsh-aliases      "$HOME/.zsh-aliases"

info "Wiring .zsh-aliases into ~/.zshrc..."
touch "$HOME/.zshrc"
if grep -q 'zsh-aliases' "$HOME/.zshrc"; then
  ok "  ~/.zshrc already sources ~/.zsh-aliases"
else
  printf '\nsource ~/.zsh-aliases\n' >> "$HOME/.zshrc"
  ok "  added 'source ~/.zsh-aliases' to ~/.zshrc"
fi

info "Installing Vim plugins..."
if [ -t 0 ]; then
  vim -N -u "$HOME/.vimrc" +'PlugInstall --sync' +qa
  ok "  done"
else
  warn "  no terminal attached – run 'vim +PlugInstall +qa' yourself"
fi

ok "All set. Open a new shell (or run: source ~/.zshrc)."
