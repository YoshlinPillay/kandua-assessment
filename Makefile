SHELL := /bin/bash
VENV  := .venv
BIN   := $(VENV)/bin

.PHONY: help venv fetch-raw lint test test-hooks dbt

help:  ## List targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

venv:  ## Create the local Python env with dev tooling
	python3.12 -m venv $(VENV)
	$(BIN)/pip install -q --upgrade pip
	$(BIN)/pip install -q -e ".[dev]"

fetch-raw:  ## Download the raw JSON files from Google Drive into data/raw (gitignored)
	$(BIN)/python -m ingestion.drive_files

lint:  ## ruff + sqlfluff + hook tests
	$(BIN)/ruff check .
	$(BIN)/ruff format --check .
	@if ls transform/models >/dev/null 2>&1; then $(BIN)/sqlfluff lint transform; fi
	tests/hooks/test_hooks.sh

test-hooks:  ## Verify the Claude Code guard hooks
	tests/hooks/test_hooks.sh

test: test-hooks  ## All tests
	$(BIN)/pytest -q

dbt:  ## Run dbt with the project profile, e.g. make dbt ARGS="build"
	cd transform && ../$(BIN)/dbt $(ARGS) --profiles-dir .
