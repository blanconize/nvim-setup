#!/usr/bin/env bash
# Runs shellcheck over the installer and its tests, from anywhere.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
shellcheck -x install.sh install/*.sh test/*.sh
