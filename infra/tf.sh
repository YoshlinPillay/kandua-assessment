#!/bin/bash
# Run Terraform (pinned official image) with the short-lived credentials of your `make aws-login` session.
# Credentials are exported into this process's environment only (never printed, never written to disk).
# Usage: infra/tf.sh <stack-dir> <terraform args...>     e.g. infra/tf.sh infra/terraform plan
set -euo pipefail

STACK=$1
shift
PROFILE=${AWS_PROFILE_NAME:-kandua}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

eval "$(docker run --rm --user "$(id -u):$(id -g)" -e HOME=/home/aws -v "$HOME/.aws:/home/aws/.aws" \
  amazon/aws-cli:2.37.7 configure export-credentials --profile "$PROFILE" --region af-south-1 --format env)"

exec docker run --rm -i --user "$(id -u):$(id -g)" \
  -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION=af-south-1 \
  -e TF_IN_AUTOMATION=1 -e HOME=/tmp \
  -v "$ROOT:/workspace" -w "/workspace/$STACK" \
  hashicorp/terraform:1.16.4 "$@"
