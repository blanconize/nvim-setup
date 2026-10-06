#!/usr/bin/env bash
# Asserts the end state install.sh promises on Linux. Run as the installed user.
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$HOME/.local/opt/node/bin:$HOME/.local/share/pnpm/bin:$HOME/.local/share/pnpm:$PATH"
# shellcheck source=test/assert.sh
source "$DOTFILES/test/assert.sh"
# shellcheck source=install/lib.sh
source "$DOTFILES/install/lib.sh"

check "nvim >= 0.11" version_ge "$(tool_version nvim)" 0.11
check "fzf >= 0.48"  version_ge "$(tool_version fzf)" 0.48
check "node >= 20"   version_ge "$(tool_version node)" 20
for bin in zsh git rg tmux jq lsof pgrep gcc gh zoxide delta lazygit tree-sitter npm pnpm pdm claude; do
  check "$bin is on PATH" command -v "$bin"
done

# shellcheck disable=SC2088 # ~ only appears in the test descriptions
{
linked() { [ "$(readlink "$1")" = "$DOTFILES/$2" ]; }
check "~/.config/nvim linked"            linked "$HOME/.config/nvim" nvim
check "~/.tmux.conf linked"              linked "$HOME/.tmux.conf" .tmux.conf
check "~/.zsh-tools linked"              linked "$HOME/.zsh-tools" .zsh-tools
check "~/.gitconfig linked"              linked "$HOME/.gitconfig" .gitconfig
check "~/.gitconfig-os is the Linux one" linked "$HOME/.gitconfig-os" .gitconfig-linux
check "~/.claude/settings.json linked"   linked "$HOME/.claude/settings.json" claude/settings.json
check "git uses gh as credential helper" \
  eq "$(git config --global --includes --get credential.helper)" '!gh auth git-credential'
}

login_shell() { basename "$(getent passwd "$(id -un)" | cut -d: -f7)"; }
check "zsh is the login shell" eq "$(login_shell)" zsh
check "a non-login zsh finds the upstream nvim" \
  eq "$(env -i HOME="$HOME" PATH=/usr/bin:/bin zsh -c 'command -v nvim')" "$HOME/.local/bin/nvim"

check "Lazy sync runs clean" nvim --headless "+Lazy! sync" +qa
for pkg in $MASON_PKGS; do
  check "Mason installed $pkg" test -d "$HOME/.local/share/nvim/mason/packages/$pkg"
done

if [ -n "${DISPLAY:-}" ]; then
  check "Nerd Font installed on a desktop" \
    test -f "$HOME/.local/share/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFontMono-Regular.ttf"
fi

finish_tests
