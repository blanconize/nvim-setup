# shellcheck shell=bash
# Helpers shared by every platform module. Sourced by install.sh and the tests.

# shellcheck disable=SC2034 # used by install.sh and test/verify.sh
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
