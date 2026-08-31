#!/usr/bin/env bash
# PreToolUse hook for Bash: blocks commands that touch a live database or
# bypass git hooks. Exit 2 = block, message on stderr goes back to Claude.
set -euo pipefail
cmd="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))')"

block() { echo "BLOCKED by ~/.claude/hooks/guard-bash.sh: $1 — the developer runs this manually." >&2; exit 2; }

# Patterns match an *invoked* command, not the same words inside a heredoc or string.
runner='(^|[;&|(`]|[[:space:]])(pnpm|npm|yarn|npx|bun)([[:space:]]+(run|exec))?[[:space:]]+'
if echo "$cmd" | grep -Eq "${runner}db:(push|reset|seed|deploy|migrate:apply|migrate:deploy)([[:space:]]|$)"; then
  block "pnpm db script against the live database"
fi
if echo "$cmd" | grep -Eq '(^|[;&|(`/]|[[:space:]])(prisma|drizzle-kit)[[:space:]]+(db[[:space:]]+push|migrate[[:space:]]+(deploy|reset)|push)([[:space:]]|$)'; then
  block "prisma/drizzle-kit apply command"
fi
if echo "$cmd" | grep -Eq '\bgit[[:space:]]+(commit|push)\b.*--no-verify'; then
  block "git --no-verify"
fi
if echo "$cmd" | grep -Eiq '^[[:space:]]*psql\b.*(drop|truncate|delete[[:space:]]+from|alter[[:space:]]+table)'; then
  block "destructive SQL via psql"
fi
exit 0
