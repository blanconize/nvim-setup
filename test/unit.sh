#!/usr/bin/env bash
# Unit tests for the installer helpers. No network, no root; runs on macOS and Linux.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOTFILES="$ROOT"
FIX="$ROOT/test/fixtures"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# shellcheck source=test/assert.sh
source "$ROOT/test/assert.sh"
# shellcheck source=install/lib.sh
source "$ROOT/install/lib.sh"
# shellcheck source=install/linux-pkg.sh
source "$ROOT/install/linux-pkg.sh"

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

# --- package manager detection and names
pm_of() { eq "$(detect_pkg_manager "$FIX/os-release/$1")" "$2"; }
check  "ubuntu uses apt"                   pm_of ubuntu apt
check  "debian uses apt"                   pm_of debian apt
check  "mint (ID_LIKE ubuntu) uses apt"    pm_of mint apt
check  "fedora uses dnf"                   pm_of fedora dnf
check  "rocky (ID_LIKE rhel) uses dnf"     pm_of rocky dnf
check  "arch uses pacman"                  pm_of arch pacman
check  "manjaro (ID_LIKE arch) uses pacman" pm_of manjaro pacman
refute "alpine is unsupported"             detect_pkg_manager "$FIX/os-release/alpine"
refute "missing os-release is unsupported" detect_pkg_manager "$TMP/nope"

for pm in apt dnf pacman; do
  for pkg in zsh git curl jq tmux lsof ripgrep zoxide unzip; do
    check "$pm installs $pkg" contains "$(pkg_names $pm)" $pkg
  done
done
check  "apt brings the C toolchain"         contains "$(pkg_names apt)" build-essential
check  "apt brings venv for pdm"            contains "$(pkg_names apt)" python3-venv
check  "dnf brings chsh"                    contains "$(pkg_names dnf)" util-linux-user
check  "pacman names gh github-cli"         contains "$(pkg_names pacman)" github-cli
refute "unknown manager has no package list" pkg_names zypper

# --- as_root: no sudo when already root (servers, containers)
# shellcheck disable=SC2329 # id/sudo stubs are called by as_root
as_uid() { local uid="$1"; ( id() { echo "$uid"; }; sudo() { echo "sudo $*"; }; as_root echo hi ); }
check "root runs commands without sudo" eq "$(as_uid 0)" hi
check "a normal user goes through sudo" eq "$(as_uid 1000)" "sudo echo hi"

finish_tests
