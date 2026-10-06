# shellcheck shell=bash
# Linux: native packages (apt/dnf/pacman), upstream tools in ~/.local, Nerd Font
# on desktops, zsh as login shell.

# shellcheck source=install/linux-pkg.sh
source "$DOTFILES/install/linux-pkg.sh"
# shellcheck source=install/upstream.sh
source "$DOTFILES/install/upstream.sh"

OS_RELEASE="${OS_RELEASE:-/etc/os-release}"
# ~/.zshenv (every zsh, also non-login terminals) and ~/.profile (bash, display managers).
# pnpm links into $PNPM_HOME/bin (current layout) or $PNPM_HOME itself (v10); PNPM_HOME is set
# here because oh-my-zsh's installer replaces the ~/.zshrc that pnpm's installer wrote it to.
# shellcheck disable=SC2016 # expanded later by the shell that reads the file
LOCAL_PATH_LINE='export PNPM_HOME="$HOME/.local/share/pnpm" PATH="$HOME/.local/bin:$HOME/.local/opt/node/bin:$HOME/.local/share/pnpm/bin:$HOME/.local/share/pnpm:$PATH"  # dotfiles: local PATH'

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
  export PATH="$LOCAL_BIN:$LOCAL_OPT/node/bin:$PNPM_HOME/bin:$PNPM_HOME:$PATH"
  if needs_epel "$OS_RELEASE"; then ensure_dnf_extra_repos "$OS_RELEASE"; fi
  # shellcheck disable=SC2046 # pkg_names is a space-separated list on purpose
  ensure_native_packages "$PM" $(pkg_names "$PM")
  if [ "$PM" = apt ]; then ensure_gh_apt; fi
  # Mason's basedpyright needs Python >= 3.10; RHEL 9 rebuilds ship 3.9 but carry python3.12
  if needs_epel "$OS_RELEASE" && ! version_ge "$(tool_version python3)" 3.10; then
    ensure_native_packages "$PM" python3.12
  fi

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
