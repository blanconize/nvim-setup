#!/usr/bin/env bash
#
# Installs these dotfiles on macOS: tooling via Homebrew, oh-my-zsh + theme,
# Neovim plugins/LSPs, and symlinks for every config file (including
# ~/.claude). Safe to re-run; existing real files are backed up as <file>.bak.

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

link() { # link <repo path> <target>
  local src="$DOTFILES/$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    ok "  $dst already linked"
    return
  fi
  if [ -e "$dst" ] || [ -L "$dst" ]; then
    warn "  backing up $dst -> $dst.bak"
    rm -rf "$dst.bak"
    mv "$dst" "$dst.bak"
  fi
  ln -s "$src" "$dst"
  ok "  linked $dst -> $src"
}

ensure_line() { # ensure_line <file> <grep pattern> <line to append>
  touch "$1"
  if grep -q "$2" "$1"; then
    ok "  $1 already contains '$2'"
  else
    printf '\n%s\n' "$3" >> "$1"
    ok "  added '$3' to $1"
  fi
}

ensure_tool zsh zsh
ensure_tool rg ripgrep
ensure_tool fzf fzf
ensure_tool nvim neovim
ensure_tool tree-sitter tree-sitter-cli   # compiles Treesitter parsers
ensure_tool tmux tmux
ensure_tool delta git-delta
ensure_tool lazygit lazygit
ensure_tool gh gh
ensure_tool zoxide zoxide
ensure_tool duti duti   # sets the default terminal app

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

info "Making iTerm2 the default terminal (.command/.tool files, x-man-page: links)..."
if [ -d "/Applications/iTerm.app" ]; then
  duti -s com.googlecode.iterm2 com.apple.terminal.shell-script all
  duti -s com.googlecode.iterm2 .command all
  duti -s com.googlecode.iterm2 .tool all
  duti -s com.googlecode.iterm2 x-man-page
  ok "  .command files now open in $(duti -x command | head -1)"
else
  warn "  iTerm2 not found – install with: brew install --cask iterm2"
fi

info "Linking config files..."
link .gitconfig        "$HOME/.gitconfig"
link .gitconfig-aviam  "$HOME/.gitconfig-aviam"
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

info "Installing Neovim plugins, parsers and language servers..."
nvim --headless "+Lazy! sync" +qa
nvim --headless -c 'lua require("nvim-treesitter").install(vim.g.ts_langs):wait(600000)' +qa
MASON_PKGS="typescript-language-server eslint_d basedpyright json-lsp html-lsp css-lsp tailwindcss-language-server lua-language-server bash-language-server yaml-language-server stylua ruff prettier"
missing=""
for pkg in $MASON_PKGS; do
  [ -d "$HOME/.local/share/nvim/mason/packages/$pkg" ] || missing="$missing $pkg"
done
if [ -n "$missing" ]; then
  nvim --headless -c "MasonInstall$missing" +qa
else
  ok "  all Mason packages already installed"
fi
ok "  done"

ok "All set. Open a new shell (or run: source ~/.zshrc), then 'dev <repo>' to start a tmux session."
