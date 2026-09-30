#!/usr/bin/env bash
# PostToolUse: lint the file the agent just wrote. On failure, exit 2 so the agent sees the errors and fixes them.
# Tools are used from .venv when present. Missing tools are skipped (and say so) so bootstrap doesn't deadlock.
set -uo pipefail

root="${CLAUDE_PROJECT_DIR:-$PWD}"
path=$(jq -r '.tool_input.file_path // empty')
[[ -z "$path" || ! -f "$path" ]] && exit 0
rel=${path#"$root/"}
bin="$root/.venv/bin"

run() {  # run <tool> <args...> — report failures back to the agent
  local out
  if ! out=$("$@" 2>&1); then
    printf 'Lint failed for %s:\n%s\n' "$rel" "$out" | tail -n 40 >&2
    exit 2
  fi
}

case "$rel" in
  transform/*.sql)
    [[ -x "$bin/sqlfluff" ]] && cd "$root/transform" && run "$bin/sqlfluff" lint "$path" ;;
  transform/*.yml|transform/*.yaml)
    [[ -x "$bin/dbt" ]] && cd "$root/transform" && run "$bin/dbt" parse --quiet ;;
  *.py)
    [[ -x "$bin/ruff" ]] && run "$bin/ruff" check "$path" && run "$bin/ruff" format --check "$path" ;;
  *.tf)
    command -v terraform >/dev/null && run terraform fmt -check "$path" ;;
esac
exit 0
