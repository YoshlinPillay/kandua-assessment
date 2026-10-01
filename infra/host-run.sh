#!/bin/bash
# Run a shell command on the AWS app host through SSM and print its output (no SSH, no plugin).
# Intended for read-only diagnostics, e.g.: infra/host-run.sh 'tail -20 /var/log/juan-bootstrap.log'
set -euo pipefail
PROFILE=${AWS_PROFILE_NAME:-kandua}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
aws() {
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/home/aws -v "$HOME/.aws:/home/aws/.aws" \
    amazon/aws-cli:2.37.7 --profile "$PROFILE" --region af-south-1 "$@"
}
instance=$("$ROOT/infra/tf.sh" infra/terraform output -raw instance_id)
params=$(jq -cn --arg c "$1" '{commands: [$c], executionTimeout: ["600"]}')
id=$(aws ssm send-command --instance-ids "$instance" --document-name AWS-RunShellScript \
  --comment "diagnostics" --parameters "$params" --query Command.CommandId --output text)
for _ in $(seq 1 60); do
  status=$(aws ssm get-command-invocation --command-id "$id" --instance-id "$instance" \
    --query Status --output text 2>/dev/null || echo Pending)
  case "$status" in Pending | InProgress | Delayed) sleep 3 ;; *) break ;; esac
done
aws ssm get-command-invocation --command-id "$id" --instance-id "$instance" \
  --query '[StandardOutputContent, StandardErrorContent]' --output text
