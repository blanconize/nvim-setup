#!/usr/bin/env bash
# Integration test: install.sh in a fresh container per supported distro.
# Usage: test/linux.sh [image...]   (default: all supported distros)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ $# -gt 0 ] || set -- ubuntu:24.04 debian:13 fedora:latest archlinux:latest

failed=""
for image in "$@"; do
  gui=0 platform=()
  [ "$image" = ubuntu:24.04 ] && gui=1   # one distro also exercises the desktop branch
  # Arch publishes amd64 only; on Apple Silicon this runs emulated and covers the x86_64 path
  case "$image" in archlinux:*) platform=(--platform linux/amd64) ;; esac
  echo "=== $image (gui=$gui)"
  if docker run --rm ${platform[@]+"${platform[@]}"} -e TEST_GUI="$gui" -v "$ROOT:/src:ro" "$image" bash /src/test/in-container.sh; then
    echo "=== $image: PASS"
  else
    echo "=== $image: FAIL"
    failed="$failed $image"
  fi
done
[ -z "$failed" ] || { echo "failed:$failed"; exit 1; }
echo "all distros passed"
