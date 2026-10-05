# Linux-Support für install.sh — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `./install.sh` richtet das Setup auf Ubuntu/Debian, Fedora und Arch (Desktop und headless/WSL) genauso ein wie heute auf macOS, ohne das Mac-Verhalten zu ändern.

**Architecture:** `install.sh` erkennt das OS, lädt `install/lib.sh` (Helfer) und `install/macos.sh` bzw. `install/linux.sh`; beide definieren `platform_preflight`, `platform_packages`, `platform_gui`, `platform_finish`, die gemeinsamen Schritte (oh-my-zsh, Claude Code, Symlinks, Neovim-Tooling) bleiben in `install.sh`. Linux installiert Basis-Pakete nativ (apt/dnf/pacman, `install/linux-pkg.sh`) und versionskritische Tools upstream nach `~/.local` (`install/upstream.sh`).

**Tech Stack:** bash (macOS: 3.2 kompatibel halten!), curl, jq, GitHub-Releases-API, Docker für Integrationstests, shellcheck.

**Spec:** `docs/superpowers/specs/2026-10-05-linux-install-design.md`

## Global Constraints

- Unterstützte Paketmanager: apt, dnf, pacman — Erkennung über `ID`/`ID_LIKE` aus `/etc/os-release`; alles andere bricht ab, **bevor** irgendetwas geändert wird.
- Architekturen: x86_64 und aarch64; sonst Abbruch vor jeder Änderung.
- Mindestversionen: neovim ≥ 0.11, fzf ≥ 0.48, node ≥ 20.
- Nichts pinnen — jeder Installer holt die aktuelle Version.
- `sudo` nur für native Pakete und `chsh`; Upstream-Tools ohne Root nach `~/.local` (`~/.local/bin`, `~/.local/opt/<tool>`). Läuft das Skript als root, kein `sudo`.
- Zweiter Lauf idempotent: keine rot (`warn`) ausgegebenen Zeilen.
- macOS-Pfad: gleiches Ergebnis wie vorher; Code wird verschoben, nicht umgeschrieben (Ausnahme: portables `set_zsh_theme`).
- Alle Skripte laufen unter macOS-`/bin/bash` 3.2 (keine `declare -A`, kein `${var,,}`, kein `mapfile`), Linux-only-Code darf bash ≥ 4 annehmen, aber die Unit-Tests sourcen ihn auch auf macOS.
- Commits: kein `--no-verify`, keine AI-Trailer; `claude/settings.json` und `nvim/lazy-lock.json` haben fremde, uncommittete Änderungen — **nie mit-stagen**, immer gezielt `git add <datei>`.
- Bevor du Installer-URLs oder Asset-Namen in Code gießt (gh-apt-Repo, pnpm-, pdm-Installer, Release-Asset-Namen), gegen die aktuelle Doku prüfen (Context7 `resolve-library-id` → `query-docs`, sonst die Release-Seite).

## Review Focus

1. **Distro hat schon ein altes Tool** (Ubuntu: `apt install neovim` → 0.9.5 in `/usr/bin`): Upstream-Version wird installiert, gewinnt auf dem `PATH`, zweiter Lauf installiert nicht erneut → Task 7 installiert in Ubuntu vorab `neovim fzf` aus apt.
2. **Nicht-Login-zsh** (GNOME Terminal, neue tmux-Fenster je nach Config) muss `~/.local/bin` auf dem `PATH` haben → PATH-Zeile geht nach `~/.zshenv` (statt `~/.zprofile`, Spec wird in Task 8 angepasst) und `~/.profile`; Task 7 `verify.sh` prüft `zsh -c 'command -v nvim'`.
3. **WSL mit WSLg** setzt `$DISPLAY`, ist aber keine Linux-Desktop-Session (Font gehört auf Windows) → Task 6 Unit-Test.
4. **Abbruch mitten im Download** (Netz weg): bestehende `~/.local/opt/nvim` bzw. `~/.local/opt/node` bleibt intakt, Rerun repariert → Task 5 Unit-Tests.
5. **Als root ausgeführt** (Server, Container): kein `sudo`-Aufruf → Task 4 Unit-Test.

---

## File Structure

| Datei | Verantwortung |
|---|---|
| `install.sh` | Einstieg: OS-Erkennung, Module laden, gemeinsame Schritte, Reihenfolge |
| `install/lib.sh` | Ausgabe (`info/ok/warn/die`), `link`, `ensure_line`, `set_zsh_theme`, `version_ge`, `tool_version`, `ensure_min_version`, `MASON_PKGS` |
| `install/macos.sh` | Homebrew, Formeln, Casks, `duti`, iTerm2-Profil (bisheriger Code) |
| `install/linux.sh` | Linux-Ablauf: Preflight, Pakete, PATH-Zeilen, GUI/Font, `chsh` |
| `install/linux-pkg.sh` | Paketmanager-Erkennung, Namens-Tabelle, `as_root`, `ensure_native_packages`, `ensure_gh_apt` |
| `install/upstream.sh` | `arch_regex`, `release_asset_url`, `install_neovim/fzf/lazygit/delta/tree_sitter/node/pnpm/pdm` |
| `.gitconfig-macos` / `.gitconfig-linux` | OS-spezifischer Credential-Helper, gelinkt nach `~/.gitconfig-os` |
| `test/assert.sh` | `check`, `refute`, `eq`, `contains`, `finish_tests` |
| `test/unit.sh` | Unit-Tests (kein Netz, kein root, macOS + Linux) |
| `test/lint.sh` | shellcheck über alle Installer-/Test-Skripte |
| `test/fixtures/` | `os-release/*`, `release.json` |
| `test/linux.sh` | Docker-Integrationstest je Distro (Host-Seite) |
| `test/in-container.sh` | Container-Seite: User anlegen, 2× install, verify |
| `test/verify.sh` | Prüft den versprochenen Endzustand auf Linux |

---

### Task 1: Test-Harness und `install/lib.sh`

**Files:**
- Create: `install/lib.sh`, `test/assert.sh`, `test/unit.sh`, `test/lint.sh`
- Modify: `install.sh` (Helfer entfernen, `lib.sh` sourcen)

**Interfaces:**
- Produces (in `install/lib.sh`):
  - `info|ok|warn <msg>`, `die <msg>` (warn + `exit 1`)
  - `link <repo path> <target>` (nutzt `$DOTFILES`), `ensure_line <file> <grep pattern> <line>`
  - `set_zsh_theme <theme> [rc file, default ~/.zshrc]`
  - `version_ge <have> <want>` → Status 0 wenn have ≥ want (numerisch, punktweise)
  - `tool_version <binary>` → erste `x.y[.z]` aus `<binary> --version`
  - `ensure_min_version <binary> <min|0> <install function>`
  - `MASON_PKGS` (String, Leerzeichen-getrennt)
- Produces (in `test/assert.sh`): `check <desc> <cmd...>`, `refute <desc> <cmd...>`, `eq <actual> <expected>`, `contains <list> <word>`, `finish_tests`

- [ ] **Step 1: shellcheck installieren (nur Dev-Werkzeug)**

Run: `brew install shellcheck`
Expected: `shellcheck --version` zeigt eine Version.

- [ ] **Step 2: `test/assert.sh` schreiben**

```bash
# shellcheck shell=bash
# Minimal assertions for the installer tests: `check` passes when the command
# succeeds, `refute` when it fails.
FAILS=0

check() {
  if "${@:2}"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); fi
}

refute() {
  if "${@:2}"; then printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); else printf 'ok   %s\n' "$1"; fi
}

eq() {
  [ "$1" = "$2" ] || { printf '     expected [%s], got [%s]\n' "$2" "$1"; return 1; }
}

contains() {
  case " $1 " in *" $2 "*) return 0 ;; esac
  printf '     [%s] not in [%s]\n' "$2" "$1"
  return 1
}

finish_tests() {
  if [ "$FAILS" -eq 0 ]; then echo "all passed"; else echo "$FAILS failed"; exit 1; fi
}
```

- [ ] **Step 3: Failing Tests in `test/unit.sh` schreiben**

```bash
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

finish_tests
```

Run: `chmod +x test/unit.sh && ./test/unit.sh`
Expected: FAIL — `install/lib.sh: No such file or directory`.

- [ ] **Step 4: `install/lib.sh` schreiben** (Helfer aus `install.sh` verschieben; `set_zsh_theme` portabel; neue Versions-Helfer; `MASON_PKGS`)

```bash
# shellcheck shell=bash
# Helpers shared by every platform module. Sourced by install.sh and the tests.

MASON_PKGS="typescript-language-server eslint_d basedpyright json-lsp html-lsp css-lsp tailwindcss-language-server lua-language-server bash-language-server yaml-language-server stylua ruff prettier"

info()  { printf '\033[36m%s\033[0m\n' "$1"; }
ok()    { printf '\033[32m%s\033[0m\n' "$1"; }
warn()  { printf '\033[31m%s\033[0m\n' "$1"; }
die()   { warn "$1"; exit 1; }

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

set_zsh_theme() { # set_zsh_theme <theme name> [rc file]: replaces or appends ZSH_THEME
  local rc="${2:-$HOME/.zshrc}" tmp
  touch "$rc"
  if grep -q "^ZSH_THEME=\"$1\"" "$rc"; then
    ok "  ZSH_THEME is already $1"
  elif grep -q '^ZSH_THEME=' "$rc"; then
    # No `sed -i`: BSD and GNU sed disagree on its syntax. `cat >` keeps the file's mode.
    tmp="$(mktemp)"
    sed "s/^ZSH_THEME=.*/ZSH_THEME=\"$1\"/" "$rc" > "$tmp" && cat "$tmp" > "$rc"
    rm -f "$tmp"
    ok "  ZSH_THEME set to $1"
  else
    printf '\nZSH_THEME="%s"\n' "$1" >> "$rc"
    ok "  ZSH_THEME=$1 added to $rc"
  fi
}

version_ge() { # version_ge <have> <want>: true when have >= want, compared field by field
  local IFS=. i h w
  local -a have want
  read -ra have <<< "$1"
  read -ra want <<< "$2"
  for ((i = 0; i < ${#want[@]} || i < ${#have[@]}; i++)); do
    h="${have[i]:-0}"; h="${h%%[!0-9]*}"; h="${h:-0}"
    w="${want[i]:-0}"; w="${w%%[!0-9]*}"; w="${w:-0}"
    ((10#$h > 10#$w)) && return 0
    ((10#$h < 10#$w)) && return 1
  done
  return 0
}

tool_version() { # tool_version <binary>: first x.y[.z] in its --version output, empty if none
  "$1" --version 2>/dev/null | head -1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -1 || true
}

ensure_min_version() { # ensure_min_version <binary> <min version, 0 = any> <install function>
  local have label="$1"
  [ "$2" = 0 ] || label="$1 >= $2"
  info "Checking for $label..."
  if command -v "$1" >/dev/null 2>&1; then
    have="$(tool_version "$1")"
    if version_ge "${have:-0}" "$2"; then
      ok "  $1 ${have:-} is already installed"
      return
    fi
    warn "  $1 ${have:-?} is too old, installing the upstream release"
  else
    warn "  installing $1"
  fi
  "$3"
}
```

- [ ] **Step 5: `install.sh` auf `lib.sh` umstellen**

In `install.sh` die Funktionen `info`, `ok`, `warn`, `link`, `ensure_line`, `set_zsh_theme` löschen und direkt nach `ZSH_CUSTOM=…` einfügen:

```bash
# shellcheck source=install/lib.sh
source "$DOTFILES/install/lib.sh"
```

Die Zeile `MASON_PKGS="…"` unten in `install.sh` löschen (kommt jetzt aus `lib.sh`).

- [ ] **Step 6: `test/lint.sh` schreiben**

```bash
#!/usr/bin/env bash
# shellcheck over the installer and its tests. Run from anywhere.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
shellcheck -x install.sh install/*.sh test/*.sh
```

- [ ] **Step 7: Tests und Lint laufen lassen**

Run: `chmod +x test/lint.sh && ./test/unit.sh && ./test/lint.sh`
Expected: alle Zeilen `ok`, `all passed`; shellcheck ohne Ausgabe. Findings beheben (nicht per `disable` wegdrücken, außer bei bewusst gewollten Fällen wie Word-Splitting — dann mit Begründungskommentar).

- [ ] **Step 8: Commit**

```bash
git add install.sh install/lib.sh test/assert.sh test/unit.sh test/lint.sh
git commit -m "refactor(install): Helfer nach install/lib.sh, portables set_zsh_theme, Unit-Tests"
```

---

### Task 2: macOS-Modul und OS-Dispatch

**Files:**
- Create: `install/macos.sh`
- Modify: `install.sh` (komplett neu strukturiert)

**Interfaces:**
- Consumes: alles aus `install/lib.sh`
- Produces: Vertrag jedes Plattform-Moduls — `platform_preflight`, `platform_packages`, `platform_gui`, `platform_finish` (keine Argumente). `install.sh` setzt `OS=macos|linux` (wird in Task 3 für `.gitconfig-$OS` genutzt).

- [ ] **Step 1: `install/macos.sh` schreiben** (Code aus `install.sh` verschoben, unverändert bis auf die Gruppierung)

```bash
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
```

- [ ] **Step 2: `install.sh` neu schreiben**

```bash
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
  Linux)  die "Linux support is not implemented yet." ;;
  *)      die "Unsupported OS $(uname -s): this installer targets macOS and Linux." ;;
esac
# shellcheck source=install/macos.sh
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
```

- [ ] **Step 3: Lint + Unit-Tests**

Run: `./test/lint.sh && ./test/unit.sh`
Expected: shellcheck still, `all passed`.

- [ ] **Step 4: Idempotenz auf diesem Mac prüfen (Regressionstest für den Mac-Pfad)**

Run: `./install.sh 2>&1 | tee "$TMPDIR/mac-install.log"; grep -c $'\033\[31m' "$TMPDIR/mac-install.log"`
Expected: Exit 0, Zähler `0` (keine roten Zeilen — alles „already installed/linked“). `Lazy! sync` kann `nvim/lazy-lock.json` ändern: **nicht** stagen.

- [ ] **Step 5: Commit**

```bash
git add install.sh install/macos.sh
git commit -m "refactor(install): macOS-Schritte nach install/macos.sh, OS-Dispatch in install.sh"
```

---

### Task 3: OS-spezifischer Git-Credential-Helper

**Files:**
- Create: `.gitconfig-macos`, `.gitconfig-linux`
- Modify: `.gitconfig:5-6`, `install.sh` (`link_configs`), `test/unit.sh`

**Interfaces:**
- Consumes: `OS` aus `install.sh`, `link` aus `lib.sh`
- Produces: `~/.gitconfig-os` → `$DOTFILES/.gitconfig-$OS` (Task 7 prüft das)

- [ ] **Step 1: Failing Tests an `test/unit.sh` anhängen** (vor `finish_tests`)

```bash
# --- git credential helper per OS
# shellcheck disable=SC2088 # the literal ~ is what .gitconfig must contain
check  ".gitconfig includes ~/.gitconfig-os" eq "$(git config -f "$ROOT/.gitconfig" include.path)" '~/.gitconfig-os'
refute ".gitconfig no longer hardcodes osxkeychain" grep -q osxkeychain "$ROOT/.gitconfig"
check  "macOS keeps the keychain helper" eq "$(git config -f "$ROOT/.gitconfig-macos" credential.helper)" osxkeychain
check  "Linux uses gh as helper (works headless)" eq "$(git config -f "$ROOT/.gitconfig-linux" credential.helper)" '!gh auth git-credential'
```

Run: `./test/unit.sh`
Expected: die vier neuen Zeilen `FAIL`, Exit 1.

- [ ] **Step 2: Implementieren**

`.gitconfig` — den Block

```
[credential]
  helper = osxkeychain
```

ersetzen durch

```
# Credential helper differs per OS: install.sh links ~/.gitconfig-os to
# .gitconfig-macos or .gitconfig-linux
[include]
  path = ~/.gitconfig-os
```

`.gitconfig-macos`:

```
[credential]
  helper = osxkeychain
```

`.gitconfig-linux`:

```
# gh stores the token itself, so this works on servers without a keyring
[credential]
  helper = !gh auth git-credential
```

In `install.sh` → `link_configs` nach `link .gitconfig-aviam …` einfügen:

```bash
  link ".gitconfig-$OS"  "$HOME/.gitconfig-os"
```

- [ ] **Step 3: Tests + Mac-Lauf**

Run: `./test/unit.sh && ./test/lint.sh && ./install.sh >/dev/null && git config --global credential.helper`
Expected: `all passed`; letzte Ausgabe `osxkeychain`. (Der neue Link erzeugt beim ersten Lauf eine grüne „linked“-Zeile — erwartet.)

- [ ] **Step 4: Commit**

```bash
git add .gitconfig .gitconfig-macos .gitconfig-linux install.sh test/unit.sh
git commit -m "feat(git): Credential-Helper pro OS über ~/.gitconfig-os"
```

---

### Task 4: Native Linux-Pakete (`install/linux-pkg.sh`)

**Files:**
- Create: `install/linux-pkg.sh`, `test/fixtures/os-release/{ubuntu,debian,mint,fedora,rocky,arch,manjaro,alpine}`
- Modify: `test/unit.sh`

**Interfaces:**
- Consumes: `info/ok/warn` aus `lib.sh`
- Produces:
  - `as_root <cmd...>` — direkt als root, sonst via `sudo`
  - `detect_pkg_manager [os-release file]` → stdout `apt|dnf|pacman`, Status 1 wenn unbekannt
  - `pkg_names <apt|dnf|pacman>` → Leerzeichen-getrennte Paketliste (ohne `gh` bei apt), Status 1 bei unbekanntem Manager
  - `pkg_is_installed <manager> <package>`
  - `ensure_native_packages <manager> <package...>` — installiert nur fehlende
  - `ensure_gh_apt` — gh aus dem GitHub-apt-Repo

- [ ] **Step 1: Fixtures anlegen**

```bash
mkdir -p test/fixtures/os-release && cd test/fixtures/os-release
printf 'ID=ubuntu\nID_LIKE=debian\nVERSION_ID="24.04"\n' > ubuntu
printf 'ID=debian\nVERSION_ID="13"\n' > debian
printf 'ID=linuxmint\nID_LIKE="ubuntu debian"\n' > mint
printf 'ID=fedora\nVERSION_ID=42\n' > fedora
printf 'ID="rocky"\nID_LIKE="rhel centos fedora"\n' > rocky
printf 'ID=arch\n' > arch
printf 'ID=manjaro\nID_LIKE=arch\n' > manjaro
printf 'ID=alpine\nVERSION_ID=3.20.0\n' > alpine
cd -
```

- [ ] **Step 2: Failing Tests an `test/unit.sh` anhängen** (Source-Zeile oben zu den anderen `source`-Zeilen, Tests vor `finish_tests`)

```bash
# shellcheck source=install/linux-pkg.sh
source "$ROOT/install/linux-pkg.sh"
```

```bash
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
as_uid() { local uid="$1"; ( id() { echo "$uid"; }; sudo() { echo "sudo $*"; }; as_root echo hi ); }
check "root runs commands without sudo" eq "$(as_uid 0)" hi
check "a normal user goes through sudo" eq "$(as_uid 1000)" "sudo echo hi"
```

Run: `./test/unit.sh`
Expected: FAIL — `install/linux-pkg.sh: No such file or directory`.

- [ ] **Step 3: Doku prüfen**

gh-apt-Repo: Context7 (`cli/cli`, Thema „install linux debian apt“) oder `https://github.com/cli/cli/blob/trunk/docs/install_linux.md`. Keyring-URL, `sources.list.d`-Zeile und Pfade mit dem Code unten abgleichen; bei Abweichung die Doku übernehmen.

- [ ] **Step 4: `install/linux-pkg.sh` schreiben**

```bash
# shellcheck shell=bash
# Native Linux packages: package-manager detection, name mapping, installation.

as_root() { # as_root <cmd...>: run directly when root (containers, servers), else via sudo
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

detect_pkg_manager() { # detect_pkg_manager [os-release file] -> apt|dnf|pacman
  local ids word
  ids="$(. "${1:-/etc/os-release}" 2>/dev/null && printf '%s %s' "${ID:-}" "${ID_LIKE:-}")" || return 1
  for word in $ids; do
    case "$word" in
      debian|ubuntu)      echo apt;    return ;;
      fedora|rhel|centos) echo dnf;    return ;;
      arch)               echo pacman; return ;;
    esac
  done
  return 1
}

pkg_names() { # pkg_names <manager>: what install.sh needs natively (apt gets gh from GitHub's repo)
  local common="zsh git curl unzip tar gzip jq tmux lsof ripgrep zoxide"
  case "$1" in
    apt)    echo "$common build-essential python3 python3-venv xz-utils procps ca-certificates" ;;
    dnf)    echo "$common gcc make python3 xz procps-ng util-linux-user gh" ;;
    pacman) echo "$common base-devel python xz procps-ng github-cli" ;;
    *)      return 1 ;;
  esac
}

pkg_is_installed() { # pkg_is_installed <manager> <package>
  case "$1" in
    # shellcheck disable=SC2016 # ${Status} is dpkg-query's format, not a shell variable
    apt)    dpkg-query -W -f='${Status}' "$2" 2>/dev/null | grep -q 'install ok installed' ;;
    dnf)    rpm -q --whatprovides "$2" >/dev/null 2>&1 ;;
    pacman) pacman -Q "$2" >/dev/null 2>&1 || pacman -Qg "$2" >/dev/null 2>&1 ;;
  esac
}

ensure_native_packages() { # ensure_native_packages <manager> <package...>
  local pm="$1" pkg
  local -a missing=()
  shift
  info "Checking native packages ($pm)..."
  for pkg in "$@"; do
    pkg_is_installed "$pm" "$pkg" || missing+=("$pkg")
  done
  if [ ${#missing[@]} -eq 0 ]; then
    ok "  all native packages already installed"
    return
  fi
  warn "  installing ${missing[*]}"
  case "$pm" in
    apt)    as_root apt-get update -qq
            as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${missing[@]}" ;;
    dnf)    as_root dnf install -y -q "${missing[@]}" ;;
    pacman) as_root pacman -Syu --needed --noconfirm "${missing[@]}" ;;  # Arch: no partial upgrades
  esac
}

ensure_gh_apt() { # Debian/Ubuntu ship an old or no gh; GitHub's own apt repository is current
  local key=/etc/apt/keyrings/githubcli-archive-keyring.gpg
  local list=/etc/apt/sources.list.d/github-cli.list
  info "Checking for gh..."
  if command -v gh >/dev/null 2>&1; then
    ok "  gh is already installed"
    return
  fi
  warn "  installing gh from cli.github.com"
  as_root mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | as_root tee "$key" >/dev/null
  as_root chmod go+r "$key"
  echo "deb [arch=$(dpkg --print-architecture) signed-by=$key] https://cli.github.com/packages stable main" \
    | as_root tee "$list" >/dev/null
  as_root apt-get update -qq
  as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq gh
}
```

- [ ] **Step 5: Tests + Lint**

Run: `./test/unit.sh && ./test/lint.sh`
Expected: `all passed`, shellcheck still.

- [ ] **Step 6: Commit**

```bash
git add install/linux-pkg.sh test/fixtures/os-release test/unit.sh
git commit -m "feat(install): Paketmanager-Erkennung und native Pakete für apt/dnf/pacman"
```

---

### Task 5: Upstream-Tools nach `~/.local` (`install/upstream.sh`)

**Files:**
- Create: `install/upstream.sh`, `test/fixtures/release.json`
- Modify: `test/unit.sh`

**Interfaces:**
- Consumes: `warn` aus `lib.sh`; `jq`, `curl`, `tar`, `xz` (native Schicht)
- Produces:
  - Variablen `LOCAL_BIN=$HOME/.local/bin`, `LOCAL_OPT=$HOME/.local/opt`, `PNPM_HOME` (Default `$HOME/.local/share/pnpm`)
  - `arch_regex [machine]` → `x86_64|amd64|x64` bzw. `aarch64|arm64`, Status 1 sonst
  - `github_release_json <owner/repo>` (Netz; in Tests überschrieben)
  - `release_asset_url <owner/repo> <regex auf Asset-Name, case-insensitiv>` → URL, Status 1 ohne Treffer
  - `install_neovim`, `install_fzf`, `install_lazygit`, `install_delta`, `install_tree_sitter`, `install_node`, `install_pnpm`, `install_pdm` — keine Argumente, Status ≠ 0 bei Fehler, bestehende Installation bleibt bei Fehler intakt

- [ ] **Step 1: Asset-Namen und Installer prüfen**

Per Context7 bzw. aktueller Release-Seite bestätigen:
- neovim: `nvim-linux-x86_64.tar.gz` / `nvim-linux-arm64.tar.gz` (Top-Level-Ordner im Tarball)
- fzf: `fzf-<v>-linux_amd64.tar.gz` / `linux_arm64`
- lazygit: `lazygit_<v>_linux_x86_64.tar.gz` / `_arm64` (Groß-/Kleinschreibung egal, Regex ist `i`)
- delta: `delta-<v>-x86_64-unknown-linux-gnu.tar.gz` / `aarch64-…`
- tree-sitter: `tree-sitter-linux-x64.gz` / `tree-sitter-linux-arm64.gz` (gzip-Einzelbinary)
- pnpm: `curl -fsSL https://get.pnpm.io/install.sh | sh -` respektiert `PNPM_HOME`/`SHELL`
- pdm: `curl -sSL https://pdm-project.org/install-pdm.py | python3 -` installiert nach `~/.local/bin`

Abweichungen: Regex/URL im Code unten entsprechend anpassen.

- [ ] **Step 2: Fixture `test/fixtures/release.json`**

```json
{
  "tag_name": "v0.11.4",
  "assets": [
    { "name": "nvim-linux-arm64.appimage",        "browser_download_url": "https://example.test/nvim-linux-arm64.appimage" },
    { "name": "nvim-linux-arm64.tar.gz",          "browser_download_url": "https://example.test/nvim-linux-arm64.tar.gz" },
    { "name": "nvim-linux-x86_64.tar.gz.zsync",   "browser_download_url": "https://example.test/nvim-linux-x86_64.tar.gz.zsync" },
    { "name": "nvim-linux-x86_64.tar.gz",         "browser_download_url": "https://example.test/nvim-linux-x86_64.tar.gz" },
    { "name": "lazygit_0.55.1_Darwin_x86_64.tar.gz", "browser_download_url": "https://example.test/lazygit_darwin.tar.gz" },
    { "name": "lazygit_0.55.1_Linux_x86_64.tar.gz",  "browser_download_url": "https://example.test/lazygit_linux.tar.gz" },
    { "name": "shasum.txt",                       "browser_download_url": "https://example.test/shasum.txt" }
  ]
}
```

- [ ] **Step 3: Failing Tests an `test/unit.sh` anhängen**

Source-Zeile oben:

```bash
# shellcheck source=install/upstream.sh
source "$ROOT/install/upstream.sh"
```

Tests vor `finish_tests`:

```bash
# --- release assets
check  "x86_64 also matches amd64/x64 spellings" eq "$(arch_regex x86_64)" 'x86_64|amd64|x64'
check  "aarch64 also matches arm64"              eq "$(arch_regex aarch64)" 'aarch64|arm64'
refute "riscv64 is unsupported"                  arch_regex riscv64

github_release_json() { cat "$FIX/release.json"; }
asset() { release_asset_url some/repo "$1" 2>/dev/null; }
check  "picks the x86_64 neovim tarball, not .zsync/.appimage" \
  eq "$(asset "^nvim-linux-($(arch_regex x86_64))\.tar\.gz$")" https://example.test/nvim-linux-x86_64.tar.gz
check  "picks the arm64 neovim tarball" \
  eq "$(asset "^nvim-linux-($(arch_regex aarch64))\.tar\.gz$")" https://example.test/nvim-linux-arm64.tar.gz
check  "matches asset names case-insensitively (lazygit's Linux_)" \
  eq "$(asset "^lazygit_.*_linux_($(arch_regex x86_64))\.tar\.gz$")" https://example.test/lazygit_linux.tar.gz
refute "fails when no asset matches" asset '^nope$'

# --- a failed download keeps the existing install
mkdir -p "$TMP/home/.local/opt/nvim/bin"
echo old > "$TMP/home/.local/opt/nvim/bin/nvim"
broken_nvim_download() { # <how>: noasset | curlfail
  local how="$1"
  ( LOCAL_OPT="$TMP/home/.local/opt"; LOCAL_BIN="$TMP/home/.local/bin"
    if [ "$how" = noasset ]; then release_asset_url() { return 1; }
    else release_asset_url() { echo https://example.test/x.tar.gz; }; curl() { return 22; }; fi
    install_neovim ) >/dev/null 2>&1
}
refute "install_neovim fails without a matching asset" broken_nvim_download noasset
refute "install_neovim fails when the download breaks" broken_nvim_download curlfail
check  "a failed neovim install leaves the old one in place" eq "$(cat "$TMP/home/.local/opt/nvim/bin/nvim")" old
check  "a failed neovim install leaves no temp dirs behind" eq "$(ls -A "$TMP/home/.local/opt")" nvim
```

Run: `./test/unit.sh`
Expected: FAIL — `install/upstream.sh: No such file or directory`.

- [ ] **Step 4: `install/upstream.sh` schreiben**

```bash
# shellcheck shell=bash
# Tools whose distro packages are missing or too old, fetched from upstream into ~/.local.
# Every installer unpacks into a temp dir first, so a failed download keeps the old version.

LOCAL_BIN="$HOME/.local/bin"
LOCAL_OPT="$HOME/.local/opt"
PNPM_HOME="${PNPM_HOME:-$HOME/.local/share/pnpm}"

arch_regex() { # arch_regex [machine]: regex for the ways release assets spell this CPU
  case "${1:-$(uname -m)}" in
    x86_64|amd64)  echo 'x86_64|amd64|x64' ;;
    aarch64|arm64) echo 'aarch64|arm64' ;;
    *)             return 1 ;;
  esac
}

github_release_json() { # github_release_json <owner/repo>
  curl -fsSL "https://api.github.com/repos/$1/releases/latest"
}

release_asset_url() { # release_asset_url <owner/repo> <asset name regex, case-insensitive>
  local url
  url="$(github_release_json "$1" | jq -r --arg re "$2" \
    'first(.assets[] | select(.name | test($re; "i")) | .browser_download_url) // empty')"
  [ -n "$url" ] || { warn "  no release asset of $1 matches /$2/ ($(uname -m))"; return 1; }
  echo "$url"
}

replace_dir() { # replace_dir <new dir> <target dir>: swap in a fully unpacked install
  rm -rf "$2"
  mv "$1" "$2"
}

install_neovim() {
  local url tmp
  url="$(release_asset_url neovim/neovim "^nvim-linux-($(arch_regex))\.tar\.gz$")" || return 1
  mkdir -p "$LOCAL_OPT" "$LOCAL_BIN"
  tmp="$(mktemp -d "$LOCAL_OPT/.nvim.XXXXXX")"
  curl -fsSL "$url" | tar -xz -C "$tmp" --strip-components=1 || { rm -rf "$tmp"; return 1; }
  replace_dir "$tmp" "$LOCAL_OPT/nvim"
  ln -sf "$LOCAL_OPT/nvim/bin/nvim" "$LOCAL_BIN/nvim"
}

install_release_binary() { # install_release_binary <owner/repo> <asset regex> <binary name>
  local url tmp bin
  url="$(release_asset_url "$1" "$2")" || return 1
  tmp="$(mktemp -d)"
  case "$url" in
    *.tar.gz) curl -fsSL "$url" | tar -xz -C "$tmp" || { rm -rf "$tmp"; return 1; } ;;
    *.gz)     curl -fsSL "$url" | gunzip > "$tmp/$3" || { rm -rf "$tmp"; return 1; } ;;
  esac
  bin="$(find "$tmp" -type f -name "$3" | head -1)"
  [ -n "$bin" ] || { warn "  $3 not found in $url"; rm -rf "$tmp"; return 1; }
  mkdir -p "$LOCAL_BIN"
  install -m 755 "$bin" "$LOCAL_BIN/$3"
  rm -rf "$tmp"
}

install_fzf()         { install_release_binary junegunn/fzf "^fzf-.*-linux_($(arch_regex))\.tar\.gz$" fzf; }
install_lazygit()     { install_release_binary jesseduffield/lazygit "^lazygit_.*_linux_($(arch_regex))\.tar\.gz$" lazygit; }
install_delta()       { install_release_binary dandavison/delta "^delta-.*-($(arch_regex))-unknown-linux-gnu\.tar\.gz$" delta; }
install_tree_sitter() { install_release_binary tree-sitter/tree-sitter "^tree-sitter-linux-($(arch_regex))\.gz$" tree-sitter; }

install_node() { # current LTS from nodejs.org, with npm (Mason needs it)
  local version node_arch tmp
  case "$(uname -m)" in
    x86_64)        node_arch=x64 ;;
    aarch64|arm64) node_arch=arm64 ;;
  esac
  version="$(curl -fsSL https://nodejs.org/dist/index.json | jq -r 'first(.[] | select(.lts != false)) | .version')" || return 1
  mkdir -p "$LOCAL_OPT"
  tmp="$(mktemp -d "$LOCAL_OPT/.node.XXXXXX")"
  curl -fsSL "https://nodejs.org/dist/$version/node-$version-linux-$node_arch.tar.xz" \
    | tar -xJ -C "$tmp" --strip-components=1 || { rm -rf "$tmp"; return 1; }
  replace_dir "$tmp" "$LOCAL_OPT/node"
}

install_pnpm() { # standalone installer; SHELL=zsh so its PATH block lands in ~/.zshrc
  curl -fsSL https://get.pnpm.io/install.sh | env SHELL="$(command -v zsh)" PNPM_HOME="$PNPM_HOME" sh -
}

install_pdm() {
  curl -fsSL https://pdm-project.org/install-pdm.py | python3 -
}
```

- [ ] **Step 5: Tests + Lint**

Run: `./test/unit.sh && ./test/lint.sh`
Expected: `all passed`, shellcheck still.

- [ ] **Step 6: Commit**

```bash
git add install/upstream.sh test/fixtures/release.json test/unit.sh
git commit -m "feat(install): Upstream-Installer für neovim, fzf, lazygit, delta, tree-sitter, node, pnpm, pdm"
```

---

### Task 6: Linux-Modul und Dispatch

**Files:**
- Create: `install/linux.sh`
- Modify: `install.sh` (`Linux)`-Zweig), `test/unit.sh`

**Interfaces:**
- Consumes: alles aus `lib.sh`, `linux-pkg.sh`, `upstream.sh`; `OS_RELEASE` (Default `/etc/os-release`, für Tests überschreibbar)
- Produces: `platform_preflight` (setzt globales `PM`), `platform_packages`, `platform_gui`, `platform_finish`, `is_gui_session [proc-version file]`, `LOCAL_PATH_LINE`

- [ ] **Step 1: Failing Tests an `test/unit.sh` anhängen**

Source-Zeile oben (ersetzt die Zeilen für `linux-pkg.sh` und `upstream.sh` — `linux.sh` lädt beide selbst):

```bash
# shellcheck source=install/linux.sh
source "$ROOT/install/linux.sh"
```

Tests vor `finish_tests`:

```bash
# --- GUI detection
printf 'Linux version 6.8.0-45-generic (buildd@lcy02)\n' > "$TMP/proc-native"
printf 'Linux version 5.15.167.4-microsoft-standard-WSL2\n' > "$TMP/proc-wsl"
gui() { DISPLAY="$1" WAYLAND_DISPLAY="$2" is_gui_session "$TMP/proc-$3"; }
check  "an X11 desktop is a GUI session"           gui :0 "" native
check  "a Wayland desktop is a GUI session"        gui "" wayland-0 native
refute "ssh/headless is no GUI session"            gui "" "" native
refute "WSLg sets DISPLAY but is no Linux desktop" gui :0 wayland-0 wsl

# --- preflight aborts before changing anything
preflight_with() { OS_RELEASE="$FIX/os-release/$1" bash -c "$(declare -f die warn detect_pkg_manager arch_regex platform_preflight); platform_preflight; echo \"pm=\$PM\"" 2>&1; }
check "preflight picks the package manager" contains "$(preflight_with fedora)" pm=dnf
check "preflight rejects unknown distros"   contains "$(preflight_with alpine)" "Unsupported distro"
refute "preflight on an unknown distro exits non-zero" preflight_with alpine
```

(`preflight_with` läuft in einer eigenen `bash`, weil `die` per `exit` abbricht; ihr Exit-Status ist der von `bash -c`.)

Run: `./test/unit.sh`
Expected: FAIL — `install/linux.sh: No such file or directory`.

- [ ] **Step 2: `install/linux.sh` schreiben**

```bash
# shellcheck shell=bash
# Linux: native packages (apt/dnf/pacman), upstream tools in ~/.local, Nerd Font
# on desktops, zsh as login shell.

# shellcheck source=install/linux-pkg.sh
source "$DOTFILES/install/linux-pkg.sh"
# shellcheck source=install/upstream.sh
source "$DOTFILES/install/upstream.sh"

OS_RELEASE="${OS_RELEASE:-/etc/os-release}"
# ~/.zshenv (every zsh, also non-login terminals) and ~/.profile (bash, display managers).
# shellcheck disable=SC2016 # expanded later by the shell that reads the file
LOCAL_PATH_LINE='export PATH="$HOME/.local/bin:$HOME/.local/opt/node/bin:$HOME/.local/share/pnpm:$PATH"  # dotfiles: local PATH'

is_gui_session() { # is_gui_session [/proc/version]: desktop session that is not WSL(g)
  [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 1
  ! grep -qi microsoft "${1:-/proc/version}" 2>/dev/null
}

platform_preflight() {
  PM="$(detect_pkg_manager "$OS_RELEASE")" \
    || die "Unsupported distro: install.sh needs apt, dnf or pacman (see $OS_RELEASE)."
  arch_regex >/dev/null || die "Unsupported CPU architecture $(uname -m): x86_64 and aarch64 only."
}

platform_packages() {
  export PATH="$LOCAL_BIN:$LOCAL_OPT/node/bin:$PNPM_HOME:$PATH"
  # shellcheck disable=SC2046 # pkg_names is a space-separated list on purpose
  ensure_native_packages "$PM" $(pkg_names "$PM")
  if [ "$PM" = apt ]; then ensure_gh_apt; fi

  ensure_min_version nvim 0.11 install_neovim
  ensure_min_version fzf 0.48 install_fzf   # `fzf --zsh` in .zsh-tools
  ensure_min_version lazygit 0 install_lazygit
  ensure_min_version delta 0 install_delta
  ensure_min_version tree-sitter 0 install_tree_sitter
  ensure_min_version node 20 install_node
  command -v npm >/dev/null 2>&1 || install_node   # Debian packages npm separately
  ensure_min_version pnpm 0 install_pnpm
  ensure_min_version pdm 0 install_pdm

  info "Putting ~/.local on PATH..."
  ensure_line "$HOME/.zshenv"  'dotfiles: local PATH' "$LOCAL_PATH_LINE"
  ensure_line "$HOME/.profile" 'dotfiles: local PATH' "$LOCAL_PATH_LINE"
}

platform_gui() {
  local dir="$HOME/.local/share/fonts/JetBrainsMonoNerdFont" tmp
  info "Checking for a graphical session..."
  if ! is_gui_session; then
    ok "  none (server, ssh or WSL) – fonts belong on the client, skipping"
    return
  fi
  ensure_native_packages "$PM" fontconfig
  info "Checking for JetBrainsMono Nerd Font..."
  if [ -f "$dir/JetBrainsMonoNerdFontMono-Regular.ttf" ]; then
    ok "  JetBrainsMono Nerd Font is already installed"
  else
    warn "  installing JetBrainsMono Nerd Font"
    tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/font.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
    mkdir -p "$dir"
    unzip -oq "$tmp/font.zip" -d "$dir"
    rm -rf "$tmp"
    fc-cache -f "$dir" >/dev/null
  fi
  info "Use a true-colour terminal with the font 'JetBrainsMono Nerd Font Mono'."
}

platform_finish() {
  local zsh_path user
  zsh_path="$(command -v zsh)"
  user="$(id -un)"
  info "Checking login shell..."
  if [ "$(basename "$(getent passwd "$user" | cut -d: -f7)")" = zsh ]; then
    ok "  zsh is already the login shell"
  else
    warn "  making zsh the login shell"
    grep -qx "$zsh_path" /etc/shells || echo "$zsh_path" | as_root tee -a /etc/shells >/dev/null
    as_root chsh -s "$zsh_path" "$user"
  fi
  ok "All set. Log in again (zsh is your login shell now), run 'gh auth login' and 'claude' once to log in, then 'dev <repo>' to start a tmux session."
}
```

- [ ] **Step 3: `install.sh` umstellen**

```bash
  Linux)  OS=linux ;;
```

statt der `die "Linux support is not implemented yet."`-Zeile. Die `# shellcheck source=install/macos.sh`-Direktive vor dem dynamischen `source` ersetzen durch:

```bash
# shellcheck source=/dev/null # install/macos.sh or install/linux.sh, both linted directly
```

- [ ] **Step 4: Tests + Lint**

Run: `./test/unit.sh && ./test/lint.sh`
Expected: `all passed`, shellcheck still.

- [ ] **Step 5: Mac-Regression**

Run: `./install.sh 2>&1 | grep -c $'\033\[31m'`
Expected: `0`.

- [ ] **Step 6: Commit**

```bash
git add install/linux.sh install.sh test/unit.sh
git commit -m "feat(install): Linux-Modul (Pakete, ~/.local-PATH, Nerd Font, Login-Shell)"
```

---

### Task 7: Docker-Integrationstests

**Files:**
- Create: `test/linux.sh`, `test/in-container.sh`, `test/verify.sh`

**Interfaces:**
- Consumes: `version_ge`, `tool_version`, `MASON_PKGS` aus `lib.sh`; Endzustand aus Tasks 3–6
- Produces: `./test/linux.sh [image...]` — Exit 0 nur wenn alle Images `PASS`

- [ ] **Step 1: Docker-Runtime sicherstellen**

Run: `docker info >/dev/null 2>&1 && echo ok`
Ist kein Docker da: **anhalten und den Nutzer fragen**, ob `brew install colima docker && colima start --cpu 4 --memory 8` (oder OrbStack) installiert werden soll. Nicht eigenmächtig installieren.

- [ ] **Step 2: `test/verify.sh` schreiben**

```bash
#!/usr/bin/env bash
# Asserts the end state install.sh promises on Linux. Run as the installed user.
set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="$HOME/.local/bin:$HOME/.local/opt/node/bin:$HOME/.local/share/pnpm:$PATH"
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

linked() { [ "$(readlink "$1")" = "$DOTFILES/$2" ]; }
check "~/.config/nvim linked"          linked "$HOME/.config/nvim" nvim
check "~/.tmux.conf linked"            linked "$HOME/.tmux.conf" .tmux.conf
check "~/.zsh-tools linked"            linked "$HOME/.zsh-tools" .zsh-tools
check "~/.gitconfig linked"            linked "$HOME/.gitconfig" .gitconfig
check "~/.gitconfig-os is the Linux one" linked "$HOME/.gitconfig-os" .gitconfig-linux
check "~/.claude/settings.json linked" linked "$HOME/.claude/settings.json" claude/settings.json
check "git uses gh as credential helper" eq "$(git config --global credential.helper)" '!gh auth git-credential'

login_shell() { basename "$(getent passwd "$(id -un)" | cut -d: -f7)"; }
check "zsh is the login shell" eq "$(login_shell)" zsh
check "a non-login zsh finds the upstream nvim" eq "$(env -i HOME="$HOME" PATH=/usr/bin:/bin zsh -c 'command -v nvim')" "$HOME/.local/bin/nvim"

check "Lazy sync runs clean" nvim --headless "+Lazy! sync" +qa
for pkg in $MASON_PKGS; do
  check "Mason installed $pkg" test -d "$HOME/.local/share/nvim/mason/packages/$pkg"
done

if [ -n "${DISPLAY:-}" ]; then
  check "Nerd Font installed on a desktop" test -f "$HOME/.local/share/fonts/JetBrainsMonoNerdFont/JetBrainsMonoNerdFontMono-Regular.ttf"
fi

finish_tests
```

- [ ] **Step 3: `test/in-container.sh` schreiben**

```bash
#!/usr/bin/env bash
# Runs inside a fresh distro container as root: creates a sudo user, installs
# twice (second run must change nothing), verifies. TEST_GUI=1 fakes a desktop.
set -euo pipefail

id_of() { . /etc/os-release; echo "$ID"; }
case "$(id_of)" in
  ubuntu|debian)
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo git ca-certificates >/dev/null
    # Old distro versions on PATH: the installer must still end up with nvim >= 0.11, fzf >= 0.48
    [ "$(id_of)" = ubuntu ] && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq neovim fzf >/dev/null ;;
  fedora) dnf install -y -q sudo git shadow-utils util-linux >/dev/null ;;
  arch)   pacman -Syu --needed --noconfirm sudo git >/dev/null ;;
esac

useradd -m -s /bin/bash dev
echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev
cp -r /src /home/dev/nvim-setup
chown -R dev: /home/dev/nvim-setup

display=""
[ "${TEST_GUI:-0}" = 1 ] && display="DISPLAY=:0"

su - dev -c "cd ~/nvim-setup && $display ./install.sh"
su - dev -c "$display ~/nvim-setup/test/verify.sh"
su - dev -c "cd ~/nvim-setup && $display ./install.sh" > /tmp/second-run.log 2>&1 \
  || { cat /tmp/second-run.log; exit 1; }
if grep -q $'\033\[31m' /tmp/second-run.log; then
  echo "FAIL: second run was not idempotent:"
  grep $'\033\[31m' /tmp/second-run.log
  exit 1
fi
echo "PASS $(id_of)"
```

- [ ] **Step 4: `test/linux.sh` schreiben**

```bash
#!/usr/bin/env bash
# Integration test: install.sh in a fresh container per supported distro.
# Usage: test/linux.sh [image...]   (default: all supported distros)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ $# -gt 0 ] || set -- ubuntu:24.04 debian:13 fedora:latest archlinux:latest

failed=""
for image in "$@"; do
  gui=0
  [ "$image" = ubuntu:24.04 ] && gui=1   # one distro also exercises the desktop branch
  echo "=== $image (gui=$gui)"
  if docker run --rm -e TEST_GUI="$gui" -v "$ROOT:/src:ro" "$image" bash /src/test/in-container.sh; then
    echo "=== $image: PASS"
  else
    echo "=== $image: FAIL"
    failed="$failed $image"
  fi
done
[ -z "$failed" ] || { echo "failed:$failed"; exit 1; }
echo "all distros passed"
```

- [ ] **Step 5: Lint und ersten Lauf (rot erwartet, wo die Realität vom Plan abweicht)**

Run: `chmod +x test/*.sh && ./test/lint.sh && ./test/linux.sh ubuntu:24.04`
Expected: entweder `PASS`, oder konkrete Fehler (z. B. abweichende Asset-Namen, fehlende Pakete). Jeden Fehler **zuerst** mit einem Unit-Test in `test/unit.sh` nachstellen, wo er sich ohne Netz nachstellen lässt (Regex, Paketliste), dann in `install/*.sh` beheben, dann erneut laufen lassen.

- [ ] **Step 6: Alle Distros grün**

Run: `./test/linux.sh`
Expected: `all distros passed`. Dauer pro Image grob 5–15 min (Mason, Treesitter).

- [ ] **Step 7: Commit**

```bash
git add test/linux.sh test/in-container.sh test/verify.sh install/ test/unit.sh test/fixtures
git commit -m "test(install): Docker-Integrationstests für Ubuntu, Debian, Fedora, Arch"
```

---

### Task 8: README und Spec nachziehen

**Files:**
- Modify: `README.md` (Abschnitt „Install“, „Terminal app“, Tabelle „What's inside“)
- Modify: `docs/superpowers/specs/2026-10-05-linux-install-design.md` (Abweichungen)

- [ ] **Step 1: README — Install-Abschnitt**

Einleitung: „Terminal-only development setup for macOS“ → „… for macOS and Linux“. Unter dem Klon-Block den Satz „The only prerequisite is a Mac with `git` …“ ersetzen durch:

```markdown
Prerequisites: `git`, and on Linux `curl` plus `sudo` rights. Supported:
macOS, and Linux distributions with **apt** (Debian, Ubuntu, Mint …),
**dnf** (Fedora, RHEL family) or **pacman** (Arch family), on x86_64 or
aarch64 — desktop, server and WSL2 alike.
```

Nach der bestehenden macOS-Aufzählung einfügen:

```markdown
On Linux it instead

- installs the basics with the native package manager (`sudo`): zsh, git,
  ripgrep, tmux, jq, lsof, zoxide, a C compiler for Treesitter, python3,
  and `gh` (on Debian/Ubuntu from GitHub's apt repository),
- installs what distros ship too old or not at all from upstream into
  `~/.local` (no root): Neovim ≥ 0.11, fzf ≥ 0.48, lazygit, delta,
  tree-sitter, Node LTS (only if the distro's is < 20 or lacks npm), pnpm,
  pdm — and puts `~/.local/bin` on the `PATH` via `~/.zshenv` and
  `~/.profile`,
- installs JetBrainsMono Nerd Font into `~/.local/share/fonts` only when it
  runs inside a graphical session (not over ssh, not on WSL — there the
  font belongs on the client),
- makes zsh the login shell (`chsh`); log in again afterwards.

Git credentials: `~/.gitconfig-os` links to `.gitconfig-macos` (keychain)
or `.gitconfig-linux` (`gh auth git-credential`, works headless).
```

- [ ] **Step 2: README — Terminal app + Tabelle**

Unter „### Terminal app“ anfügen:

```markdown
On a Linux desktop pick any true-colour terminal (e.g. Ghostty, WezTerm,
Kitty, GNOME Terminal) and set the font to *JetBrainsMono Nerd Font Mono*;
the iTerm2 profile is macOS-only.
```

Tabelle „What's inside“ um diese Zeilen ergänzen:

```markdown
| `install.sh`, `install/` | Installer: `lib.sh` helpers, `macos.sh` (Homebrew/iTerm2), `linux.sh` + `linux-pkg.sh` (apt/dnf/pacman) + `upstream.sh` (tools into `~/.local`). |
| `test/` | `unit.sh` (helpers, no network), `lint.sh` (shellcheck), `linux.sh` (installs in Ubuntu/Debian/Fedora/Arch containers and verifies; needs Docker). |
```

Und in der `.gitconfig`-Zeile „osxkeychain“ ersetzen durch „credential helper per OS via `~/.gitconfig-os`“.

- [ ] **Step 3: Spec — Abweichungen festhalten**

In `docs/superpowers/specs/2026-10-05-linux-install-design.md`:
- Abschnitt „Schicht 2“: „über `ensure_line` in `~/.zprofile` (und `~/.profile` …)“ → „in `~/.zshenv` (jede zsh, auch Nicht-Login-Terminals) und `~/.profile`“.
- Abschnitt „Architektur“: vierte Funktion `platform_preflight` (prüft Distro/Architektur, bevor etwas geändert wird) ergänzen.
- „Versionsauflösung“: „über die Releases-API mit `jq`, Asset per Regex (case-insensitiv)“.

- [ ] **Step 4: Gate**

Run: `./test/lint.sh && ./test/unit.sh && ./test/linux.sh && ./install.sh 2>&1 | grep -c $'\033\[31m'`
Expected: shellcheck still, `all passed`, `all distros passed`, `0`.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/superpowers/specs/2026-10-05-linux-install-design.md
git commit -m "docs: Linux-Installation in README und Spec"
```
