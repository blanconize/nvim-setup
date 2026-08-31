#!/usr/bin/env bash
#
# Generates an iTerm2 dynamic profile "honukai" from honukai.itermcolors
# (single source of truth for the colours) plus the Nerd Font, and makes it
# the default profile. iTerm2 picks dynamic profiles up live; the default
# switch needs iTerm2 to be closed, otherwise it overwrites the setting on quit.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE_NAME="honukai"
PROFILE_GUID="817D8E7D-51BB-41C1-B443-608CAC10E15E"
FONT="JetBrainsMonoNFM-Regular 12"
TARGET="$HOME/Library/Application Support/iTerm2/DynamicProfiles/$PROFILE_NAME.json"

ok()   { printf '\033[32m%s\033[0m\n' "$1"; }
warn() { printf '\033[31m%s\033[0m\n' "$1"; }

mkdir -p "$(dirname "$TARGET")"
plutil -convert json -o - "$HERE/$PROFILE_NAME.itermcolors" \
  | jq --indent 2 \
       --arg name "$PROFILE_NAME" --arg guid "$PROFILE_GUID" --arg font "$FONT" \
       '{ Profiles: [ . + {
            Name: $name,
            Guid: $guid,
            "Normal Font": $font,
            "Dynamic Profile Parent Name": "Default"
          } ] }' \
  > "$TARGET"
ok "  wrote $TARGET"

if [ "$(defaults read com.googlecode.iterm2 "Default Bookmark Guid" 2>/dev/null)" = "$PROFILE_GUID" ]; then
  ok "  $PROFILE_NAME is already the default profile"
elif pgrep -xq iTerm2; then
  warn "  iTerm2 is running – quit it and re-run ./install.sh to make '$PROFILE_NAME' the default profile"
  warn "  (or pick it under Settings → Profiles → Other Actions → Set as Default)"
else
  defaults write com.googlecode.iterm2 "Default Bookmark Guid" -string "$PROFILE_GUID"
  ok "  $PROFILE_NAME set as default profile"
fi
