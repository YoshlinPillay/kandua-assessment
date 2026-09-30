# CLAUDE.md — Juan the Drinker (Kandua DE assessment)

Read this file fully before doing any work in this repository.

## Mission
We are building an open-source ELT + analytics solution for "Juan the Drinker": the bars he visits, the
beverages he drinks and how often. The brief is `docs/assessment/assessment_brief.pdf` (local only, not in git).
The requirement checklist is `docs/assessment/requirements.md`. Every requirement there must map to a
file in this repo before we call the work done.

Kandua grades **how the agent was driven** as much as the result. A human (Yoshlin) owns every decision
and every number. Your job is to propose, implement and verify. Never decide silently.

## Stack (decided — do not substitute without asking)
| Layer | Tool | Location |
|---|---|---|
| Ingestion (E+L) | dlt → Postgres `raw` schema | `ingestion/` |
| Storage | PostgreSQL 16 (local: compose, cloud: AWS RDS) | `docker-compose.yml`, `infra/terraform/` |
| Transform (T) | dbt Core: `staging` → `core` (3NF OLTP) → `marts` (star) | `transform/` |
| Orchestration | Dagster (`dagster-dlt`, `dagster-dbt`) | `orchestration/` |
| Semantic layer | Metrics in dbt YAML `meta` → Lightdash; Cube models **generated** via `cube_dbt` | `transform/models/marts/*.yml`, `semantic/cube/` |
| BI | Lightdash (charts as code) | `lightdash/` |
| Conversational | Streamlit + Claude tool-use over Cube REST API | `chat/` |
| Cloud | AWS: RDS + one EC2 via Terraform, deployed by GitHub Actions OIDC | `infra/terraform/`, `.github/workflows/` |

## Hard rules
1. **Profile before modeling.** Never assume the shape, types, keys or cleanliness of raw data. Claims about
   the data must cite `docs/data_profile.md` or a query you ran. Use the `profile-raw-data` skill.
2. **Raw is immutable.** Never hand-edit raw files or the `raw` schema. All fixes happen in dbt `staging`
   and are documented in `docs/data_profile.md` under "Cleaning decisions".
3. **The ERM is the source of truth.** `docs/erm/transactional.dbml` defines the `core` schema. When one
   changes, change the other in the same commit. CI fails on drift (`tests/test_erm_drift.py`).
4. **Metrics are defined exactly once**, in dbt YAML `meta` on mart models. Never hand-write a metric in
   Cube, Lightdash or the chat app. Cube files in `semantic/cube/` are generated. Do not edit them by hand.
5. **Every number must be traceable.** Every answer (Q1–Q7) has a SQL file in `transform/analyses/`, an
   independent pandas recomputation in `tests/`, and a dashboard tile backed by a dbt metric.
6. **Interpretation calls belong to the human.** Examples: what "drunk", "last month" or "alcoholic" means,
   and how duplicates are handled. Propose options with the numbers each one produces, then ask. Record the
   decision in `docs/decisions.md`.
7. **No secrets in git.** Use `.env` (gitignored), `.env.example` with placeholders, and AWS SSM for cloud.
   See `docs/conventions/security.md`.
8. **Infrastructure changes are human-triggered.** Never run `terraform apply/destroy` or any
   destructive SQL (`DROP`, `TRUNCATE`, `DELETE` without `WHERE`) against a database. Hooks block this.
   Prepare the command and ask the user to run it with `! <command>`.
9. **Log corrections.** When the user corrects you, or you catch your own wrong assumption, append an entry
   to `AI_WORKFLOW.md` → "Corrections log" (what you assumed, what was true, how it was caught).

## Conventions (read the relevant one before writing code)
- Data modeling: `docs/conventions/modeling.md`
- SQL style: `docs/conventions/sql_style.md` (enforced by sqlfluff)
- Data quality: `docs/conventions/data_quality.md`
- Security: `docs/conventions/security.md`
- Definition of done: `docs/conventions/definition_of_done.md`

## Working mode
- We work **phase by phase** (P1 guardrails → P2 profile → P3 ERM → P4 load → P5 answers → P6 semantic/BI/chat
  → P7 AWS → P8 docs). Stop at the end of each phase and give the user a checkpoint summary: what was
  built, what was verified and how, and which decisions are open.
- Prefer frameworks over custom code (the brief is explicit). Before writing a custom script, check whether
  dlt, dbt, Dagster, Cube or Lightdash already does it.
- For a second opinion on models or SQL, use the `data-reviewer` subagent (read-only).

## Local environment notes
- Host ports in use by other services: 80, 443, 5055, 6767, 6868, 6881, 7878, 8080, 8090, 8096, 8191, 8989,
  9000, 9696. Our ports: Postgres **5433**, Dagster **3001**, Lightdash **8100**, Cube **4000**, chat **8501**.
- Python tooling lives in `.venv/` (`make venv`). Run dbt via `make dbt ARGS="..."` so the profile/env is set.
