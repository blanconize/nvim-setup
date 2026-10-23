#!/usr/bin/env bash
# Tests the `dev` tmux layout (.zsh-tools) and the Ctrl-a v toggle (.tmux.conf)
# on a private tmux server: own HOME and TMUX_TMPDIR, stubbed nvim/claude.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
# shellcheck source=test/assert.sh
source "$ROOT/test/assert.sh"

export HOME="$TMP/home" TMUX_TMPDIR="$TMP/sock" SHELL=/bin/sh
unset TMUX
mkdir -p "$HOME" "$TMUX_TMPDIR" "$TMP/bin" "$TMP/repo"
ln -s "$ROOT/.tmux.conf" "$HOME/.tmux.conf"
# dev types `nvim` and `claude --ide` into the panes; keep them inert
printf '#!/bin/sh\nexec sleep 600\n' > "$TMP/bin/nvim"
cp "$TMP/bin/nvim" "$TMP/bin/claude"
chmod +x "$TMP/bin/nvim" "$TMP/bin/claude"
export PATH="$TMP/bin:$PATH"
trap 'tmux kill-server 2>/dev/null; rm -rf "$TMP"' EXIT

run_dev() { # run_dev <cols> <lines> [dev args...] -> session name "repo"
  tmux kill-server 2>/dev/null
  zsh -c 'source "$1"; shift; COLUMNS=$1 LINES=$2; shift 2; dev "$@"' _ \
    "$ROOT/.zsh-tools" "$@" "$TMP/repo" >/dev/null 2>&1
}

# "<left> <top> <width> <height>" of a pane in the edit window (0 = nvim, 1 = claude)
pane() { tmux list-panes -t '=repo:edit' -F '#{pane_left} #{pane_top} #{pane_width} #{pane_height}' | sed -n "$(($1 + 1))p"; }
# shellcheck disable=SC2046 # word-splitting the four numbers per pane is the point
side_by_side() { set -- $(pane 0) $(pane 1); [ $# -eq 8 ] && [ "$1" -eq 0 ] && [ "$5" -gt "$1" ] && [ "$6" -eq "$2" ]; }
# shellcheck disable=SC2046
stacked()      { set -- $(pane 0) $(pane 1); [ $# -eq 8 ] && [ "$2" -eq 0 ] && [ "$6" -gt "$2" ] && [ "$5" -eq "$1" ]; }
width_pct()  { local w ww; w=$(pane 0 | cut -d' ' -f3); ww=$(tmux display -p -t '=repo:edit' '#{window_width}'); echo $(( w * 100 / ww )); }
height_pct() { local h wh; h=$(pane 0 | cut -d' ' -f4); wh=$(tmux display -p -t '=repo:edit' '#{window_height}'); echo $(( h * 100 / wh )); }
# send-keys bypasses key bindings, so run the command bound to `prefix v` instead
press_prefix_v() {
  tmux list-keys -T prefix | sed -n 's/^bind-key  *-T prefix v  *//p' > "$TMP/binding"
  [ -s "$TMP/binding" ] && tmux source-file "$TMP/binding"
}
near() { [ "$1" -ge $(($2 - 2)) ] && [ "$1" -le $(($2 + 2)) ] || { printf '     %s is not ~%s\n' "$1" "$2"; return 1; }; }

run_dev 240 60
check "a wide terminal puts nvim and claude side by side" side_by_side
check "nvim gets ~55% of the width"                      near "$(width_pct)" 55
check "the shell window still exists"                    tmux has-session -t '=repo:shell'

run_dev 100 80
check "a portrait terminal stacks nvim above claude" stacked
check "nvim gets ~60% of the height"                 near "$(height_pct)" 60

run_dev 240 60 -v
check "dev -v stacks even on a wide terminal" stacked
run_dev 100 80 -h
check "dev -h goes side by side even in portrait" side_by_side

run_dev 240 60
check "Ctrl-a v is bound"                       press_prefix_v
check "Ctrl-a v flips side by side to stacked" stacked
check "nvim keeps ~60% after flipping"         near "$(height_pct)" 60
press_prefix_v
check "Ctrl-a v flips back"                    side_by_side
check "nvim is back at ~55% of the width"      near "$(width_pct)" 55

finish_tests
