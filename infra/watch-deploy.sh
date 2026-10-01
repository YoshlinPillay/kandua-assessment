#!/bin/bash
# Wait for the latest `make tf-deploy` (SSM command) to finish and print its deploy steps and errors.
# Reads AWS's record of the command (not files on the host, which diagnostics commands also write to).
set -euo pipefail
PROFILE=${AWS_PROFILE_NAME:-kandua}
aws() {
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/home/aws -v "$HOME/.aws:/home/aws/.aws" \
    amazon/aws-cli:2.37.7 --profile "$PROFILE" --region af-south-1 "$@"
}
# --max-items 1: the CLI paginates and applies the query per page, so take only the newest command.
read -r cid instance < <(aws ssm list-commands --max-items 1 \
  --query "Commands[?Comment=='make tf-deploy'] | [0].[CommandId, InstanceIds[0]]" --output text | head -1)
echo "command $cid on $instance"
for _ in $(seq 1 60); do
  status=$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$instance" \
    --query Status --output text 2>/dev/null || echo Pending)
  case "$status" in Pending | InProgress | Delayed) sleep 30 ;; *) break ;; esac
done
echo "status: $status"
aws ssm get-command-invocation --command-id "$cid" --instance-id "$instance" \
  --query StandardOutputContent --output text | grep -E '\[deploy|explores|Total|Admin|Reviewer|rror' || true
aws ssm get-command-invocation --command-id "$cid" --instance-id "$instance" \
  --query StandardErrorContent --output text | grep -E 'RUN_SUCCESS|RUN_FAILURE|Error|ENOTFOUND' |
  grep -v ASSET | tail -5 || true
