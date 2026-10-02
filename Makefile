SHELL := /bin/bash
VENV  := .venv
BIN   := $(VENV)/bin

# AWS CLI via its official image, run as the calling user so ~/.aws stays user-owned (the root-owned files
# it otherwise writes break boto3/Terraform). Auth is `aws login` short-lived credentials, no access keys.
AWS_PROFILE_NAME ?= kandua
AWS_CLI_BATCH = docker run --rm --user $(shell id -u):$(shell id -g) -e HOME=/home/aws \
	-v $(HOME)/.aws:/home/aws/.aws amazon/aws-cli:2.37.7 --profile $(AWS_PROFILE_NAME) --region af-south-1
TF := infra/tf.sh infra/terraform
AWS_CLI := docker run --rm -it --user $(shell id -u):$(shell id -g) -e HOME=/home/aws \
	-v $(HOME)/.aws:/home/aws/.aws amazon/aws-cli:2.37.7

# Load .env (if present) and export it to every recipe, so dlt, dbt and pytest see the same settings.
-include .env
export

.PHONY: help venv up down fetch-raw load pipeline dagster-run dagster-dev lightdash-deploy screenshot screenshots chat bakeoff aws-login aws-whoami tf-fmt tf-validate tf-bootstrap tf-init tf-plan tf-apply tf-output tf-deploy tf-invites tf-credentials tf-destroy docs lint test test-hooks dbt

help:  ## List targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' Makefile | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

venv:  ## Create the local Python env with dev tooling
	python3.12 -m venv $(VENV)
	$(BIN)/pip install -q --upgrade pip
	$(BIN)/pip install -q -e ".[dev]"

up:  ## Start the local stack (needs .env)
	docker compose up -d --wait

down:  ## Stop the local stack (keeps data volumes)
	docker compose down

fetch-raw:  ## Download the raw JSON files from Google Drive into data/raw (gitignored)
	$(BIN)/python -m ingestion.drive_files

load:  ## dlt: Google Drive JSON -> Postgres raw schema
	$(BIN)/python -m ingestion.pipeline

pipeline: load  ## Full ELT: dlt load, then dbt deps + build (models, seeds, tests)
	$(MAKE) dbt ARGS="deps --quiet"
	$(MAKE) dbt ARGS="build"
	$(MAKE) dbt ARGS="docs generate --quiet"  # catalog.json: real column types for Cube + the dbt docs site

dagster-run:  ## Run the whole ELT job through Dagster (same as clicking Materialize all)
	mkdir -p orchestration/.dagster_home
	DAGSTER_HOME=$(CURDIR)/orchestration/.dagster_home $(BIN)/dagster job execute -m orchestration.definitions -j juan_elt

dagster-dev:  ## Dagster UI locally on :3001 (the compose service does the same in a container)
	mkdir -p orchestration/.dagster_home
	DAGSTER_HOME=$(CURDIR)/orchestration/.dagster_home $(BIN)/dagster dev -m orchestration.definitions -p 3001

lightdash-deploy:  ## Deploy the dbt project (metrics in marts YAML) to Lightdash; needs LIGHTDASH_API_KEY in .env
	docker compose --profile tools run --rm -T --entrypoint /app/deploy.sh lightdash-cli

screenshot:  ## Export the Lightdash dashboard as docs/images/dashboard.png (Lightdash's own headless export)
	docker compose --profile tools run --rm -T --entrypoint node lightdash-cli /app/export-dashboard.js
	cp lightdash/_dashboard.png docs/images/dashboard.png && rm -f lightdash/_dashboard.png  # cp: container writes as root

chat:  ## Conversational analytics UI on :8501 (Bedrock via your `make aws-login` session + local Cube)
	AWS_PROFILE=$(AWS_PROFILE_NAME) $(BIN)/streamlit run chat/app.py --server.port 8501 --server.address 0.0.0.0 --server.headless true --browser.gatherUsageStats false

bakeoff:  ## Ask Q1–Q7 to every candidate model on Bedrock, grade correctness + grounding -> docs/bakeoff.md
	AWS_PROFILE=$(AWS_PROFILE_NAME) $(BIN)/python -m chat.bakeoff $(MODELS)  # e.g. make bakeoff MODELS=openai.gpt-oss-120b-1:0

aws-login:  ## Sign in to AWS with console credentials (browser on any device; valid up to 12h)
	$(AWS_CLI) login --remote --profile $(AWS_PROFILE_NAME) --region af-south-1

aws-whoami:  ## Show the AWS identity the session resolves to
	$(AWS_CLI) sts get-caller-identity --profile $(AWS_PROFILE_NAME)

tf-fmt:  ## Format Terraform
	docker run --rm --user $(shell id -u):$(shell id -g) -v $(CURDIR):/w -w /w hashicorp/terraform:1.16.4 fmt -recursive infra/terraform

tf-validate:  ## Validate both Terraform stacks (no AWS access needed)
	for d in infra/terraform/bootstrap infra/terraform; do \
	  docker run --rm --user $(shell id -u):$(shell id -g) -e HOME=/tmp -e TF_DATA_DIR=/tmp/tfvalidate -v $(CURDIR):/w -w /w/$$d --entrypoint sh hashicorp/terraform:1.16.4 -c 'terraform init -backend=false -input=false >/dev/null && \
	  terraform validate' || exit 1; done

tf-bootstrap:  ## [human] One-time: create the S3 bucket for Terraform state (local state)
	infra/tf.sh infra/terraform/bootstrap init -input=false
	infra/tf.sh infra/terraform/bootstrap apply

tf-init:  ## Init the main stack against the remote state bucket
	$(TF) init -input=false -reconfigure \
	  -backend-config="bucket=juan-tfstate-$$($(AWS_CLI_BATCH) sts get-caller-identity --query Account --output text)"

tf-plan:  ## Show what Terraform would change (writes tf.plan for tf-apply)
	$(TF) plan -input=false -out=tf.plan

tf-apply:  ## [human] Apply the reviewed plan from tf-plan
	$(TF) apply -input=false tf.plan

tf-output:  ## URLs, endpoints and IDs of the deployment
	$(TF) output

tf-deploy:  ## [human] Redeploy the app on the EC2 host via SSM (pulls main, re-runs deploy/aws/deploy.sh)
	$(AWS_CLI_BATCH) ssm send-command --instance-ids "$$($(TF) output -raw instance_id)" \
	  --document-name AWS-RunShellScript --comment "make tf-deploy" \
	  --parameters 'commands=["source /etc/profile.d/juan.sh && /opt/juan/app/deploy/aws/deploy.sh"],executionTimeout=["3600"]' \
	  --query Command.CommandId --output text

tf-destroy:  ## [human] Delete the whole AWS deployment (the state bucket from tf-bootstrap is kept)
	$(TF) destroy

screenshots:  ## Docs screenshots via the stack's headless browser: Dagster lineage + chat (needs AWS login)
	docker compose build dagster-webserver
	docker rm -f juan-chat-shot >/dev/null 2>&1 || true
	docker run -d --name juan-chat-shot --network juan_default --user $(shell id -u):$(shell id -g) -e HOME=/home/app \
	  -v $(HOME)/.aws:/home/app/.aws --env-file .env -e AWS_PROFILE=$(AWS_PROFILE_NAME) -e AWS_REGION=af-south-1 \
	  -e CUBE_URL=http://cube:4000/cubejs-api/v1 juan-dagster:local streamlit run chat/app.py --server.port 8501 \
	  --server.address 0.0.0.0 --server.headless true --browser.gatherUsageStats false >/dev/null
	sleep 8
	docker compose exec -T -e CHAT_URL=http://juan-chat-shot:8501 lightdash node - < docs/screenshots.js > /tmp/juan-shots.json
	docker rm -f juan-chat-shot >/dev/null
	$(BIN)/python -c "import json,base64; [open(f'docs/images/{k}.png','wb').write(base64.b64decode(v)) for k,v in json.load(open('/tmp/juan-shots.json')).items()]"

tf-invites:  ## Print the Lightdash login links created on the AWS host (via SSM; no SSH or plugin needed)
	@id=$$($(AWS_CLI_BATCH) ssm send-command --instance-ids "$$($(TF) output -raw instance_id)" \
	  --document-name AWS-RunShellScript --parameters 'commands=["cat /opt/juan/lightdash-invites.txt"]' \
	  --query Command.CommandId --output text); sleep 4; \
	$(AWS_CLI_BATCH) ssm get-command-invocation --command-id "$$id" \
	  --instance-id "$$($(TF) output -raw instance_id)" --query StandardOutputContent --output text

tf-credentials:  ## Print reviewer logins (URLs + passwords). Run in YOUR terminal, not via an AI agent session.
	@echo "Chat + Dagster basic auth   user: juan"
	@echo "                            password: $$($(AWS_CLI_BATCH) ssm get-parameter --name /juan/basic-auth-password --with-decryption --query Parameter.Value --output text)"
	@echo "Database (read-only, TLS)   host: $$($(TF) output -raw warehouse_host)  port: 5432  db: juan  sslmode: require"
	@echo "                            user: juan_reader"
	@echo "                            password: $$($(AWS_CLI_BATCH) ssm get-parameter --name /juan/postgres-reader-password --with-decryption --query Parameter.Value --output text)"
	@echo "Lightdash                   $$($(TF) output -raw lightdash_url) (logins set via 'make tf-invites' links)"

docs:  ## Re-embed the Q1–Q7 analysis SQL into docs/ANSWERS.md
	$(BIN)/python docs/embed_sql.py

lint:  ## ruff + sqlfluff + hook tests
	$(BIN)/ruff check .
	$(BIN)/ruff format --check .
	@if ls transform/models >/dev/null 2>&1; then $(BIN)/sqlfluff lint transform; fi
	tests/hooks/test_hooks.sh

test-hooks:  ## Verify the Claude Code guard hooks
	tests/hooks/test_hooks.sh

test: test-hooks  ## All tests (compiles the Q1–Q7 analyses first so pytest can run them)
	$(MAKE) dbt ARGS="compile --select path:analyses --quiet"
	$(BIN)/pytest -q

dbt:  ## Run dbt with the project profile, e.g. make dbt ARGS="build"
	cd transform && ../$(BIN)/dbt $(ARGS) --profiles-dir .
