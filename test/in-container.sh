#!/usr/bin/env bash
# Runs inside a fresh distro container as root: creates a sudo user, installs
# twice (second run must change nothing), verifies. TEST_GUI=1 fakes a desktop.
set -euo pipefail

# shellcheck source=/dev/null
id_of() { . /etc/os-release; echo "$ID"; }
case "$(id_of)" in
  ubuntu|debian)
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq sudo git ca-certificates >/dev/null
    # Old distro versions on PATH: the installer must still end up with nvim >= 0.11, fzf >= 0.48
    if [ "$(id_of)" = ubuntu ]; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y -qq neovim fzf >/dev/null
    fi ;;
  fedora|rocky|almalinux) dnf install -y -q sudo git shadow-utils util-linux >/dev/null ;;
  arch)
    # The Arch image is amd64-only; emulated on an arm64 host, the kernel rejects
    # pacman's x86_64 seccomp sandbox. Real Arch machines keep the sandbox.
    sed -i '/^\[options\]/a DisableSandbox' /etc/pacman.conf
    pacman -Syu --needed --noconfirm sudo git >/dev/null ;;
esac

useradd -m -s /bin/bash dev
echo 'dev ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/dev
cp -r /src /home/dev/nvim-setup
chown -R dev: /home/dev/nvim-setup

display=""
if [ "${TEST_GUI:-0}" = 1 ]; then display="DISPLAY=:0"; fi

su - dev -c "cd ~/nvim-setup && $display ./install.sh"
su - dev -c "$display ~/nvim-setup/test/verify.sh"
su - dev -c "cd ~/nvim-setup && $display ./install.sh" > /tmp/second-run.log 2>&1 \
  || { cat /tmp/second-run.log; exit 1; }
if grep -qF $'\033[31m' /tmp/second-run.log; then
  echo "FAIL: second run was not idempotent:"
  grep -F $'\033[31m' /tmp/second-run.log
  exit 1
fi
echo "PASS $(id_of)"
