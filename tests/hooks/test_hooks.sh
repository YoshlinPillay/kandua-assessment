#!/usr/bin/env bash
# Deterministic tests for the Claude Code guard hooks: they must block what CLAUDE.md forbids
# and let normal work through. Run by `make test` and CI.
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
export CLAUDE_PROJECT_DIR="$root"
fails=0

check() {  # check <expected: block|allow> <hook> <json>
  local expected=$1 hook=$2 json=$3 code
  printf '%s' "$json" | "$root/.claude/hooks/$hook" >/dev/null 2>&1
  code=$?
  local got=allow; [[ $code -eq 2 ]] && got=block
  if [[ $got != "$expected" ]]; then
    echo "FAIL [$hook] expected $expected, got $got (exit $code): $json"; fails=$((fails + 1))
  fi
}
file() { printf '{"tool_input":{"file_path":"%s/%s"}}' "$root" "$1"; }
bash_cmd() { jq -cn --arg c "$1" '{tool_input:{command:$c}}'; }

# guard_files.sh
check block guard_files.sh "$(file .env)"
check block guard_files.sh "$(file infra/.env.prod)"
check allow guard_files.sh "$(file .env.example)"
check block guard_files.sh "$(file infra/terraform/terraform.tfstate)"
check block guard_files.sh "$(file data/raw/bars.json)"
check block guard_files.sh "$(file semantic/cube/model/cubes/fct_drink.yml)"
check allow guard_files.sh "$(file semantic/cube/model/cubes/marts.yml.jinja)"
check allow guard_files.sh "$(file semantic/cube/model/globals.py)"
check allow guard_files.sh "$(file transform/models/core/bar.sql)"
check allow guard_files.sh "$(file docs/data_profile.md)"

# guard_bash.sh
check block guard_bash.sh "$(bash_cmd 'cd infra/terraform && terraform apply -auto-approve')"
check block guard_bash.sh "$(bash_cmd 'docker run hashicorp/terraform destroy')"
check allow guard_bash.sh "$(bash_cmd 'terraform plan -out=tf.plan')"
check block guard_bash.sh "$(bash_cmd 'psql -c "DROP TABLE core.bar"')"
check block guard_bash.sh "$(bash_cmd 'psql -c "truncate raw.visit_events"')"
check block guard_bash.sh "$(bash_cmd 'psql -c "delete from core.drink;"')"
check allow guard_bash.sh "$(bash_cmd 'psql -c "delete from core.drink where drink_id = 1"')"
check block guard_bash.sh "$(bash_cmd 'docker compose down -v')"
check allow guard_bash.sh "$(bash_cmd 'docker compose down')"
check block guard_bash.sh "$(bash_cmd 'git push --force origin main')"
check allow guard_bash.sh "$(bash_cmd 'git push origin main')"
check block guard_bash.sh "$(bash_cmd 'cat .env')"
check allow guard_bash.sh "$(bash_cmd 'cat .env.example')"
check block guard_bash.sh "$(bash_cmd 'grep KEY ./.env')"
check block guard_bash.sh "$(bash_cmd 'source .env && env')"
check allow guard_bash.sh "$(bash_cmd 'ls docs/data.env.md')"
check block guard_bash.sh "$(bash_cmd 'aws rds delete-db-instance --db-instance-identifier x')"
check allow guard_bash.sh "$(bash_cmd 'aws sts get-caller-identity')"
check allow guard_bash.sh "$(bash_cmd 'make dbt ARGS="build"')"

# lint_changed.sh must reject badly styled SQL and accept a clean model (skipped if the venv isn't built)
if [[ -x "$root/.venv/bin/sqlfluff" ]]; then
  bad="$root/transform/models/_hooktest_bad.sql"
  printf 'SELECT A,B FROM foo\n' > "$bad"
  check block lint_changed.sh "$(file transform/models/_hooktest_bad.sql)"
  rm -f "$bad"
  check allow lint_changed.sh "$(file transform/models/core/drink.sql)"
fi

if [[ $fails -gt 0 ]]; then echo "$fails hook test(s) failed"; exit 1; fi
echo "all hook tests passed"
