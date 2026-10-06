#!/usr/bin/env bash
# Unit tests for the installer helpers. No network, no root; runs on macOS and Linux.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES="$ROOT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test/assert.sh
source "$ROOT/test/assert.sh"
# shellcheck source=install/lib.sh
source "$ROOT/install/lib.sh"

# --- version_ge / tool_version / ensure_min_version
check  "0.11.4 satisfies 0.11"                    version_ge 0.11.4 0.11
refute "0.10.4 does not satisfy 0.11"             version_ge 0.10.4 0.11
check  "0.48 satisfies 0.48.0"                    version_ge 0.48 0.48.0
check  "22.11.0 satisfies 20"                     version_ge 22.11.0 20
refute "9.0 does not satisfy 20 (numeric, not lexical)" version_ge 9.0 20
check  "anything satisfies 0"                     version_ge 0 0

mkdir -p "$TMP/bin"
printf '#!/bin/sh\necho "NVIM v0.10.4"\n' > "$TMP/bin/oldtool"
printf '#!/bin/sh\necho "newtool 0.11.4 (build abc)"\n' > "$TMP/bin/newtool"
chmod +x "$TMP/bin/oldtool" "$TMP/bin/newtool"

check "tool_version reads 'NVIM v0.10.4'" eq "$(PATH="$TMP/bin:$PATH" tool_version oldtool)" 0.10.4

INSTALLED=""
fake_install() { INSTALLED=yes; }
run_ensure() { # run_ensure <binary> <min> <expected INSTALLED>
  INSTALLED=""
  PATH="$TMP/bin:$PATH" ensure_min_version "$1" "$2" fake_install >/dev/null
  eq "$INSTALLED" "$3"
}
check "installs when the tool is too old"     run_ensure oldtool 0.11 yes
check "skips a tool that is new enough"       run_ensure newtool 0.11 ""
check "installs a missing tool"               run_ensure missingtool 0 yes
printf '#!/bin/sh\necho "no version here"\n' > "$TMP/bin/noversion"
chmod +x "$TMP/bin/noversion"
check "a tool without a version counts as too old" run_ensure noversion 0.11 yes
check "tool_version stays quiet under set -e" bash -ec "source '$ROOT/install/lib.sh'; v=\$(PATH='$TMP/bin':\$PATH tool_version noversion); [ -z \"\$v\" ]"

# --- set_zsh_theme (portable: BSD and GNU sed)
printf 'export ZSH=x\nZSH_THEME="robbyrussell"\nplugins=(git)\n' > "$TMP/zshrc"
set_zsh_theme honukai "$TMP/zshrc" >/dev/null
check "replaces an existing ZSH_THEME" eq "$(grep '^ZSH_THEME=' "$TMP/zshrc")" 'ZSH_THEME="honukai"'
check "keeps the rest of ~/.zshrc"     eq "$(wc -l < "$TMP/zshrc" | tr -d ' ')" 3
: > "$TMP/emptyrc"
set_zsh_theme honukai "$TMP/emptyrc" >/dev/null
check "appends ZSH_THEME when missing" grep -qx 'ZSH_THEME="honukai"' "$TMP/emptyrc"

# --- git credential helper per OS
# shellcheck disable=SC2088 # the literal ~ is what .gitconfig must contain
check  ".gitconfig includes ~/.gitconfig-os" eq "$(git config -f "$ROOT/.gitconfig" include.path)" '~/.gitconfig-os'
refute ".gitconfig no longer hardcodes osxkeychain" grep -q osxkeychain "$ROOT/.gitconfig"
check  "macOS keeps the keychain helper" eq "$(git config -f "$ROOT/.gitconfig-macos" credential.helper)" osxkeychain
check  "Linux uses gh as helper (works headless)" eq "$(git config -f "$ROOT/.gitconfig-linux" credential.helper)" '!gh auth git-credential'

finish_tests
