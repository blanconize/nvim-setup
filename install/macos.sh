# shellcheck shell=bash
# macOS: Homebrew formulae and casks, iTerm2 as default terminal and profile.

ensure_brew() {
  info "Checking for Homebrew..."
  if ! command -v brew >/dev/null 2>&1; then
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
  fi
  if command -v brew >/dev/null 2>&1; then
    ok "  Homebrew is already installed"
  else
    warn "  installing Homebrew"
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
  fi
  ensure_line "$HOME/.zprofile" 'brew shellenv' "eval \"\$($(command -v brew) shellenv)\""
}

ensure_tool() { # ensure_tool <binary> <brew formula>
  info "Checking for $1..."
  if command -v "$1" >/dev/null 2>&1; then
    ok "  $1 is already installed"
  else
    warn "  installing $1"
    brew install "$2"
  fi
}

ensure_cask() { # ensure_cask <brew cask> <path or file that proves it is installed>
  info "Checking for $1..."
  if [ -e "$2" ] || brew list --cask "$1" >/dev/null 2>&1; then
    ok "  $1 is already installed"
  else
    warn "  installing $1"
    brew install --cask "$1"
  fi
}

platform_preflight() { :; }

platform_packages() {
  ensure_brew
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
  ensure_tool jq jq
  ensure_tool duti duti   # sets the default terminal app
  ensure_tool node node   # Mason installs ts_ls/eslint_d/prettier via npm
  ensure_tool pnpm pnpm
  ensure_tool pdm pdm
}

platform_gui() {
  ensure_cask iterm2 /Applications/iTerm.app
  ensure_cask font-jetbrains-mono-nerd-font "$HOME/Library/Fonts/JetBrainsMonoNerdFontMono-Regular.ttf"

  info "Making iTerm2 the default terminal (.command/.tool files, x-man-page: links)..."
  duti -s com.googlecode.iterm2 com.apple.terminal.shell-script all
  duti -s com.googlecode.iterm2 .command all
  duti -s com.googlecode.iterm2 .tool all
  duti -s com.googlecode.iterm2 x-man-page
  ok "  .command files now open in $(duti -x command | head -1)"

  info "Installing iTerm2 profile (colours + font)..."
  "$DOTFILES/iterm2/profile.sh"
}

platform_finish() {
  ok "All set. Open a new iTerm2 window, run 'gh auth login' and 'claude' once to log in, then 'dev <repo>' to start a tmux session."
}
