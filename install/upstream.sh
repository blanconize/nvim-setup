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
  [ -n "$url" ] || { warn "  no release asset of $1 matches /$2/ ($(uname -m))" >&2; return 1; }
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
  [ -n "$bin" ] || { warn "  $3 not found in $url" >&2; rm -rf "$tmp"; return 1; }
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
