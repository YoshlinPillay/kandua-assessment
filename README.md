# Juan the Drinker 🍺

Kandua Data Engineer assessment. An open-source ELT pipeline, semantic layer, dashboard and conversational
assistant that answers questions about Juan's drinking habits. **Every number is traceable** to a dbt metric
or SQL query, and is checked against an independent pandas computation.

| | |
|---|---|
| **Answers (Q1–Q10), ERM, SQL** | [docs/ANSWERS.md](docs/ANSWERS.md) |
| **Architecture, decisions, trade-offs** | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · [docs/decisions.md](docs/decisions.md) |
| **How the AI agent was used and guard-railed** | [AI_WORKFLOW.md](AI_WORKFLOW.md) · [CLAUDE.md](CLAUDE.md) · [.claude/](.claude/) |
| **Data profile and cleaning decisions** | [docs/data_profile.md](docs/data_profile.md) |
| **Chat model bake-off** | [docs/bakeoff.md](docs/bakeoff.md) |
| **Tool evaluation: Altimate Code** | [docs/altimate-evaluation.md](docs/altimate-evaluation.md) |

| Q | Answer |
|---|---|
| 1 Beverage type drunk most | **Beer** (1,595 servings) |
| 2 Most-visited bar | **Yours Truly** (207; Jerry's 206) |
| 3 Favourite beer | **Castle Lite** (754 servings) |
| 4 Visits without a drink | **104** |
| 5 Times drunk, last month | **1** (2019-08-31) |
| 6 Alcoholic by NHS 14 units/week? | **Yes**: 33.24 units/week, 87 of 90 weeks over |
| 7 Saved on happy hours | **R 21,587.09** |

![Dashboard](docs/images/dashboard.png)

## Stack

| Layer | Tool | |
|---|---|---|
| Ingestion | [dlt](https://dlthub.com) | Drive JSON → Postgres `raw` |
| Warehouse | PostgreSQL 16 | `raw` → `staging` → `core` (3NF) → `marts` (star) |
| Transformation | [dbt Core](https://www.getdbt.com) | enforced contracts, 79 data tests |
| Orchestration | [Dagster](https://dagster.io) | dlt + dbt as assets, tests as asset checks |
| Metrics | dbt YAML | written once, used by both consumers below |
| Dashboard | [Lightdash](https://lightdash.com) | 14 charts + 1 dashboard as code |
| Semantic API | [Cube](https://cube.dev) | generated from the dbt manifest at runtime |
| Conversational | Streamlit + Amazon Bedrock (gpt-oss-120b) | read-only Cube tools, topic guardrail |
| Cloud | AWS (Terraform): EC2 + RDS + S3, af-south-1 | GitHub OIDC, budget alerts |

Diagrams and the reasoning are in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Run it locally

**Prerequisites:** Docker with Compose v2+, Python 3.12, `make`, `openssl`. About 8 GB RAM for the full
stack. Ports used: 5433 (Postgres), 3001 (Dagster), 8100 (Lightdash), 4000 (Cube), 8501 (chat), 9100 (MinIO).

```bash
git clone https://github.com/YoshlinPillay/kandua-assessment.git && cd kandua-assessment

# 1. Settings: copy the template and generate every password/secret (stays on your machine, gitignored)
cp .env.example .env
for v in POSTGRES_ADMIN_PASSWORD POSTGRES_READER_PASSWORD LIGHTDASH_SECRET LIGHTDASH_DB_PASSWORD \
         MINIO_ROOT_PASSWORD CUBEJS_API_SECRET; do
  sed -i "s|^$v=changeme|$v=$(openssl rand -hex 24)|" .env
done

# 2. Python tooling, then the stack
make venv
make up            # postgres, dagster, lightdash (+ db, minio, headless browser), cube

# 3. Load and transform: dlt -> dbt build (models + tests) -> dbt docs (for Cube)
make pipeline
make test          # answers (SQL = pandas = marts = Cube = Lightdash), ERM drift, roles, hooks
```

| Service | URL | Notes |
|---|---|---|
| Dagster | http://localhost:3001 | Asset lineage. **Materialize all** re-runs the pipeline. |
| Lightdash | http://localhost:8100 | First time only: see below |
| Cube playground | http://localhost:4000 | Generated cubes and measures |
| Chat | http://localhost:8501 | `make chat` (needs AWS, see below) |

**Lightdash, first time:** open http://localhost:8100, create your admin account, and skip "connect project".
Then go to *Settings → Personal access tokens*, create one, and put it in `.env` as `LIGHTDASH_API_KEY=...`.
Then run:

```bash
make lightdash-deploy   # dbt project (marts only) + charts + dashboard, all linted against Lightdash's schemas
make screenshot         # optional: re-export docs/images/dashboard.png through Lightdash itself
```

**Chat (optional; needs an AWS account with Bedrock access in us-east-1):**

```bash
make aws-login          # browser sign-in with your console user; short-lived credentials, no access keys
make chat               # http://localhost:8501
make bakeoff            # optional: golden questions x3 against the model -> docs/bakeoff.md
```

Other useful targets: `make help`, `make dagster-run` (pipeline through Dagster), `make docs` (re-embed SQL
into ANSWERS.md), `make lint`, `make down` (stop; data volumes are kept).

## Tests and quality gates

| Check | Proves |
|---|---|
| `dbt build` (79 tests) | Keys, relationships, accepted values, value rules, reconciliation of raw/staging/core/marts. Warn-level tests keep known data quirks visible. |
| `tests/answers/` | Each Q1–Q7 answer in SQL **equals** an independent pandas implementation, and the star schema reproduces it |
| `tests/test_semantic_parity.py` | Cube and every saved Lightdash chart return the verified answers |
| `tests/test_erm_drift.py` | `docs/erm/*.dbml` matches the dbt contracts **and** the live database |
| `tests/test_reader_role.py` | The reviewer role can read core/marts and can't write or see raw/staging |
| `tests/test_cube_generator.py`, `test_lightdash_content.py` | Every dbt metric becomes exactly one Cube measure. Every chart field exists. |
| `tests/test_chat_agent.py` | Tool loop, member validation, topic guardrail, nudge, bake-off grader |
| `tests/hooks/test_hooks.sh` | The Claude Code guardrail hooks block what they should, and only that |

## CI/CD

- **`.github/workflows/ci.yml`** runs on every push and PR:
  1. lint (ruff, sqlfluff offline, gitleaks, hook tests);
  2. the full pipeline on a throwaway Postgres from the same compose file (dlt → dbt build → pytest →
     Dagster job);
  3. Terraform `fmt` + `validate`.
- **`.github/workflows/deploy.yml`** uses GitHub **OIDC** to assume an AWS role, so no AWS keys are stored in
  GitHub. It runs `terraform plan` on PRs that touch `infra/`, and redeploys the app on the EC2 host through
  SSM on pushes to `main`. `terraform apply` is never automated. It's dormant until you set these repository
  variables: `AWS_ROLE_ARN` (from `make tf-output`), `ALERT_EMAIL` and `ADMIN_EMAIL`.

Locally, `pre-commit install` gives the same lint gates on every commit.

## Deploy to AWS

Infrastructure is in `infra/terraform/` (Terraform 1.16, run through its official container, so nothing is
installed locally). Region **af-south-1**, with Bedrock in **us-east-1**. It costs about **USD 3/day**; a
USD 20/month budget alert is included.

```bash
make aws-login                                  # short-lived credentials (console user + SignInLocalDevelopmentAccess)
cp infra/terraform/terraform.tfvars.example infra/terraform/terraform.tfvars   # set alert_email + admin_email
make tf-bootstrap                               # once: S3 bucket for Terraform state
make tf-init
make tf-plan                                    # review what will be created
make tf-apply                                   # ~10 min, plus ~10 min for the host's first deploy
make tf-output                                  # URLs, RDS endpoint, GitHub role ARN
```

The host deploys itself on first boot (`deploy/aws/deploy.sh`). It sets up the RDS roles, starts the stack,
runs the pipeline, and deploys Lightdash. Lightdash login links for you (admin) and the reviewers (viewer) are
then on the host:

```bash
make tf-invites    # reads /opt/juan/lightdash-invites.txt through SSM (no SSH, no plugin)
```

Redeploy after code changes: `make tf-deploy`, or push to `main` with the workflow enabled.
**Tear down:** `make tf-destroy`.

Reviewer credentials (read-only database login, basic-auth password) and the live URLs are shared in the
delivered answers document, **never in this repository**.

## Repository layout

```
ingestion/            dlt source (Google Drive -> raw)
transform/            dbt project: staging, core (3NF), marts (star + metrics), analyses (Q1–Q7 SQL), tests
orchestration/        Dagster definitions (dlt + dbt assets)
semantic/cube/        Cube config; cubes generated from the dbt manifest at runtime
lightdash/            charts and dashboard as code
chat/                 conversational assistant, bake-off, off-topic GIFs
tests/                pytest + hook tests
infra/terraform/      AWS (bootstrap state bucket + main stack)
deploy/aws/           host deploy script, warehouse roles SQL, Caddyfile
docker/               images and init scripts
docs/                 answers, architecture, decisions, data profile, ERM, conventions, images
.claude/              agent setup: settings + hooks, skills, reviewer subagent
```

## Working with the AI agent

This project was built with Claude Code, under explicit guardrails: project rules in `CLAUDE.md`, conventions
in `docs/conventions/`, hooks that block secrets access and irreversible commands and lint every file the
agent writes, skills, and a read-only reviewer subagent. Every interpretation of the questions was decided by
a human. [AI_WORKFLOW.md](AI_WORKFLOW.md) documents the work split, the guardrails and why, and **39 logged
corrections**, including what caught each one.
