#!/usr/bin/env bash
# PreToolUse guard for Bash. Blocks irreversible / human-only operations (CLAUDE.md rules 7 and 8).
# Exit 2 = block + explain to the agent, which should hand the command to the user via `! <cmd>`.
set -euo pipefail

cmd=$(jq -r '.tool_input.command // empty')
[[ -z "$cmd" ]] && exit 0
lc=$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')

block() { echo "BLOCKED by .claude/hooks/guard_bash.sh: $1. Prepare the command and ask the user to run it with '! <command>'." >&2; exit 2; }

grep -Eq 'terraform[^|;&]*[[:space:]](apply|destroy|import|state[[:space:]]+(rm|mv|push))' <<<"$lc" \
  && block "terraform apply/destroy/state changes are human-triggered"
grep -Eq '(^|[^a-z_])(drop[[:space:]]+(table|schema|database|role|user)|truncate[[:space:]])' <<<"$lc" \
  && block "destructive SQL (DROP/TRUNCATE) against a database"
grep -Eq 'delete[[:space:]]+from[[:space:]]+[a-z0-9_."]+[[:space:]]*(;|"|'"'"'|$)' <<<"$lc" \
  && block "DELETE without WHERE"
grep -Eq 'docker[[:space:]]+(compose[[:space:]]+down[^|;&]*(-v|--volumes)|volume[[:space:]]+(rm|prune)|system[[:space:]]+prune)' <<<"$lc" \
  && block "removing docker volumes destroys data (and this host runs other services)"
grep -Eq 'git[[:space:]]+push[^|;&]*(--force|[[:space:]]-f([[:space:]]|$))' <<<"$lc" \
  && block "force-push"
grep -Eq '(^|[[:space:];&|(])(cat|less|more|head|tail|bat|grep|source|\.)[[:space:]]+([^|;&]*[[:space:]/])?\.env([[:space:]]|$|;|\||\))' <<<"$cmd" \
  && block "reading .env would expose secrets in the transcript"
grep -Eq 'aws[[:space:]][^|;&]*[[:space:]](delete-|terminate-|rm[[:space:]])' <<<"$lc" \
  && block "destructive AWS CLI call"
exit 0
