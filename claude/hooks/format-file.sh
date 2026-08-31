#!/usr/bin/env bash
# PostToolUse hook for Edit|Write: format the touched file with the project's
# own Prettier (or ruff for Python) so Claude's edits match editor output.
set -uo pipefail
file="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))')"
[ -n "$file" ] && [ -f "$file" ] || exit 0

dir="$(dirname "$file")"
root=""
while [ "$dir" != "/" ]; do
  if [ -f "$dir/package.json" ] || [ -f "$dir/pyproject.toml" ]; then root="$dir"; break; fi
  dir="$(dirname "$dir")"
done
[ -n "$root" ] || exit 0

case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.json|*.css|*.md|*.mdx|*.yaml|*.yml|*.vue)
    prettier="$root/node_modules/.bin/prettier"
    [ -x "$prettier" ] || prettier="$HOME/.local/share/nvim/mason/bin/prettier"
    if [ -x "$prettier" ]; then
      (cd "$root" && "$prettier" --log-level warn --write "$file") || true
    fi;;
  *.py)
    if command -v ruff >/dev/null 2>&1; then
      (cd "$root" && ruff format --quiet "$file") || true
    fi;;
esac
exit 0
