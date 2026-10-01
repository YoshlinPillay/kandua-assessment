SHELL := /bin/bash
VENV  := .venv
BIN   := $(VENV)/bin

# AWS CLI via its official image, run as the calling user so ~/.aws stays user-owned (the root-owned files
# it otherwise writes break boto3/Terraform). Auth is `aws login` short-lived credentials, no access keys.
AWS_PROFILE_NAME ?= kandua
AWS_CLI := docker run --rm -it --user $(shell id -u):$(shell id -g) -e HOME=/home/aws \
	-v $(HOME)/.aws:/home/aws/.aws amazon/aws-cli:2.37.7

# Load .env (if present) and export it to every recipe, so dlt, dbt and pytest see the same settings.
-include .env
export

.PHONY: help venv up down fetch-raw load pipeline dagster-run dagster-dev lightdash-deploy screenshot chat bakeoff aws-login aws-whoami docs lint test test-hooks dbt

help:  ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

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
	AWS_PROFILE=$(AWS_PROFILE_NAME) $(BIN)/streamlit run chat/app.py --server.port 8501 --server.address 0.0.0.0

bakeoff:  ## Ask Q1–Q7 to every candidate model on Bedrock, grade correctness + grounding -> docs/bakeoff.md
	AWS_PROFILE=$(AWS_PROFILE_NAME) $(BIN)/python -m chat.bakeoff $(MODELS)  # e.g. make bakeoff MODELS=openai.gpt-oss-120b-1:0

aws-login:  ## Sign in to AWS with console credentials (browser on any device; valid up to 12h)
	$(AWS_CLI) login --remote --profile $(AWS_PROFILE_NAME) --region af-south-1

aws-whoami:  ## Show the AWS identity the session resolves to
	$(AWS_CLI) sts get-caller-identity --profile $(AWS_PROFILE_NAME)

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
