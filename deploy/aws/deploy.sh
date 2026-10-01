#!/bin/bash
# Deploy / redeploy the stack on the EC2 host. Idempotent. Runs as root via user_data (first boot) or SSM
# (`make tf-deploy` / .github/workflows/deploy.yml). Secrets come from SSM + Secrets Manager via the instance
# role and are written to a root-only .env. Nothing secret is printed.
set -euo pipefail

PROJECT="${JUAN_PROJECT:-juan}"
REGION="${AWS_REGION:-af-south-1}"
REF="${JUAN_GIT_REF:-main}"
APP=/opt/$PROJECT/app
COMPOSE=(docker compose -f docker-compose.yml -f docker-compose.aws.yml)
LOG=/var/log/juan-deploy.log
# Full log on the host: SSM truncates command output at 24 KB, which Dagster's debug output fills.
[ "${JUAN_DEPLOY_UPDATED:-}" = 1 ] || : > "$LOG"
exec > >(tee -a "$LOG") 2>&1
log() { echo "[deploy $(date -u +%H:%M:%S)] $*"; }
trap 'log "FAILED at line $LINENO (exit $?); full log: $LOG"' ERR

cd "$APP"
if [ "${JUAN_DEPLOY_UPDATED:-}" != 1 ]; then
  log "updating code to origin/$REF"
  git fetch --quiet origin "$REF" && git checkout --quiet -B "$REF" "origin/$REF"
  # This script just replaced itself on disk, but bash is still executing the copy it already read.
  # Re-exec so the rest of the deploy runs the NEW version (a stale run once skipped a fix entirely).
  JUAN_DEPLOY_UPDATED=1 exec "$APP/deploy/aws/deploy.sh"
fi

# ---- 1. Secrets and settings -> root-only .env ------------------------------------------------------------
param() { aws ssm get-parameter --region "$REGION" --with-decryption --name "/$PROJECT/$1" --query Parameter.Value --output text; }
RDS_HOST=$(param config/rds-host)
DOMAIN=$(param config/public-domain)
MASTER=$(aws secretsmanager get-secret-value --region "$REGION" --secret-id "$(param config/rds-master-secret)" \
  --query SecretString --output text)
BASIC_AUTH_HASH=$(docker run --rm caddy:2.10-alpine caddy hash-password --plaintext "$(param basic-auth-password)")
mkdir -p "/opt/$PROJECT/state" && chmod 700 "/opt/$PROJECT/state"
umask 077
cat > .env <<ENV
POSTGRES_HOST=$RDS_HOST
POSTGRES_PORT=5432
POSTGRES_DB=juan
POSTGRES_SSLMODE=require
POSTGRES_ADMIN_USER=juan_loader
POSTGRES_ADMIN_PASSWORD=$(param postgres-loader-password)
POSTGRES_READER_USER=juan_reader
POSTGRES_READER_PASSWORD=$(param postgres-reader-password)
LIGHTDASH_SECRET=$(param lightdash-secret)
LIGHTDASH_DB_PASSWORD=$(param lightdash-db-password)
LIGHTDASH_API_KEY=$(jq -r '.token // empty' /opt/$PROJECT/state/lightdash-bot.json 2>/dev/null)
LIGHTDASH_SITE_URL=https://lightdash.$DOMAIN
LIGHTDASH_S3_BUCKET=$(param config/lightdash-bucket)
CUBEJS_API_SECRET=$(param cubejs-api-secret)
BEDROCK_REGION=$(param config/bedrock-region)
CHAT_MODEL_ID=$(param config/bedrock-model-id)
AWS_REGION=$REGION
DOMAIN=$DOMAIN
BASIC_AUTH_HASH='$BASIC_AUTH_HASH'
JUAN_STATE_DIR=/opt/$PROJECT/state
ENV
umask 022
log ".env written (root-only)"

# ---- 2. Warehouse roles and schemas on RDS (master login used only here) ----------------------------------
log "initialising warehouse roles on RDS"
docker run --rm -i \
  -e PGPASSWORD="$(jq -r .password <<<"$MASTER")" -e PGSSLMODE=require \
  postgres:16-alpine psql -v ON_ERROR_STOP=1 -h "$RDS_HOST" -U "$(jq -r .username <<<"$MASTER")" -d juan \
  -v loader_pw="$(param postgres-loader-password)" -v reader_pw="$(param postgres-reader-password)" \
  < deploy/aws/init-warehouse.sql

# ---- 3. Services ------------------------------------------------------------------------------------------
log "building and starting services"
"${COMPOSE[@]}" up -d --build --remove-orphans --wait

# ---- 4. Pipeline: dlt load + dbt build (Dagster), then the dbt catalog Cube reads -------------------------
log "running the ELT job"
if "${COMPOSE[@]}" exec -T dagster-webserver dagster job execute -m orchestration.definitions -j juan_elt \
    > /var/log/juan-elt.log 2>&1; then
  log "ELT job: $(grep -o 'RUN_SUCCESS.*' /var/log/juan-elt.log | tail -1)"
else
  log "ELT job failed:"; grep -E 'RUN_FAILURE|Error|error' /var/log/juan-elt.log | tail -5; exit 1
fi
"${COMPOSE[@]}" exec -T -w /app/transform dagster-webserver dbt docs generate --profiles-dir . --quiet
mkdir -p transform/target
for artefact in manifest.json catalog.json; do  # Cube reads these from the host's transform/target
  "${COMPOSE[@]}" cp "dagster-webserver:/app/transform/target/$artefact" "transform/target/$artefact"
done
"${COMPOSE[@]}" restart cube

# ---- 5. Semantic layer + dashboard as code ---------------------------------------------------------------
log "bootstrapping Lightdash (organisation + deploy user + API token, first run only)"
"${COMPOSE[@]}" --profile tools run --rm -T --entrypoint node lightdash-cli /app/bootstrap.js
token=$(jq -r .token "/opt/$PROJECT/state/lightdash-bot.json")
sed -i "s|^LIGHTDASH_API_KEY=.*|LIGHTDASH_API_KEY=$token|" .env  # the CLI container reads it from .env
log "deploying Lightdash project, charts and dashboard"
"${COMPOSE[@]}" --profile tools run --rm -T --entrypoint dbt lightdash-cli deps --profiles-dir .  # host clone
"${COMPOSE[@]}" --profile tools run --rm -T --entrypoint /app/deploy.sh lightdash-cli
"${COMPOSE[@]}" --profile tools run --rm -T --entrypoint node lightdash-cli /app/invite-users.js \
  "$(param config/lightdash-admin-mail)" > "/opt/$PROJECT/lightdash-invites.txt"
chmod 600 "/opt/$PROJECT/lightdash-invites.txt"

log "done: https://lightdash.$DOMAIN  https://chat.$DOMAIN  https://dagster.$DOMAIN"
log "Lightdash invite links: sudo cat /opt/$PROJECT/lightdash-invites.txt (via SSM Session Manager)"
