#!/usr/bin/env bash
# PreToolUse guard for file-writing tools (Edit/Write/MultiEdit/NotebookEdit).
# Blocks writes that violate CLAUDE.md hard rules. Exit 2 = block + explain to the agent.
set -euo pipefail

path=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty')
[[ -z "$path" ]] && exit 0
rel=${path#"${CLAUDE_PROJECT_DIR:-$PWD}/"}

block() { echo "BLOCKED by .claude/hooks/guard_files.sh: $1 (path: $rel)" >&2; exit 2; }

case "$rel" in
  .env.example) ;;                                   # placeholders only — allowed
  .env|.env.*|*/.env|*/.env.*)
    block "secrets files are human-managed (docs/conventions/security.md). Ask the user to edit .env." ;;
  *.tfstate|*.tfstate.*)
    block "Terraform state must never be edited by hand." ;;
  data/raw/*)
    block "raw data is immutable (CLAUDE.md rule 2). Fix it in dbt staging instead." ;;
  semantic/cube/model/*)
    block "Cube models are generated from dbt YAML (CLAUDE.md rule 4). Edit transform/models/marts/*.yml and run 'make cube'." ;;
  *secrets.toml)
    block "dlt secrets are human-managed. Use env vars / .env." ;;
esac
exit 0
