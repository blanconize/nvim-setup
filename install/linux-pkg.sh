# shellcheck shell=bash
# Native Linux packages: package-manager detection, name mapping, installation.

as_root() { # as_root <cmd...>: run directly when root (containers, servers), else via sudo
  if [ "$(id -u)" -eq 0 ]; then "$@"; else sudo "$@"; fi
}

detect_pkg_manager() { # detect_pkg_manager [os-release file] -> apt|dnf|pacman
  local ids word
  # shellcheck source=/dev/null
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
  # shellcheck disable=SC2016 # ${Status} is dpkg-query's format, not a shell variable
  case "$1" in
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
