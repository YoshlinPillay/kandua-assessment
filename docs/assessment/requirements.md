# Requirements traceability

This checklist is derived from the brief (`assessment_brief.pdf`, local only). Each line maps to where it's satisfied.
Status: ☐ todo · ◐ in progress · ☑ done (verified).

## Tasks
| # | Requirement | Where | Status |
|---|---|---|---|
| 01 | Agent setup and guardrails (instructions, skills, agents, hooks, deterministic checks) | `CLAUDE.md`, `.claude/`, `docs/conventions/`, `.pre-commit-config.yaml`, `.github/workflows/ci.yml` | ◐ |
| 02 | ERM from the UML (diagram as code) | `docs/erm/transactional.dbml`, `docs/erm/README.md` | ☑ (approved; drift-tested) |
| 03 | Implement tables in an open-source SQL DB, running locally with minimal effort | `docker-compose.yml`, `transform/models/core/` | ☑ (dbt build green, live drift test) |
| 03+ | Optional cloud deploy | `infra/terraform/`, `.github/workflows/deploy.yml` | ☐ |
| 04 | Explore the raw files and load them with an ELT tool | `docs/data_profile.md`, `ingestion/`, `orchestration/` | ☑ (dlt load via Dagster, counts asserted) |
| 05 Q1 | Most-drunk beverage type | `transform/analyses/q1_*.sql` | ☑ (SQL = pandas, tested) |
| 05 Q2 | Most-visited bar | `transform/analyses/q2_*.sql` | ☑ (SQL = pandas, tested) |
| 05 Q3 | Favourite beer brand | `transform/analyses/q3_*.sql` | ☑ (SQL = pandas, tested) |
| 05 Q4 | Visits without a drink | `transform/analyses/q4_*.sql` | ☑ (SQL = pandas, tested) |
| 05 Q5 | Times drunk last month (14 units) | `transform/analyses/q5_*.sql` | ☑ (SQL = pandas, tested) |
| 05 Q6 | Alcoholic per NHS 14 units/week? | `transform/analyses/q6_*.sql` | ☑ (SQL = pandas, tested) |
| 05 Q7 | Money saved on happy hours (50%) | `transform/analyses/q7_*.sql` | ☑ (SQL = pandas, tested) |
| 05 Q8 | Does the transactional model respect 1NF/2NF/3NF? | `docs/ANSWERS.md#q8` | ☑ |
| 05 Q9 | Analytical model proposal | `docs/erm/analytical.dbml`, `transform/models/marts/` | ☑ (built, reconciled) |
| 05 Q10 | Does the analytical model respect the NFs? | `docs/ANSWERS.md#q10` | ☑ |
| 06 | Dashboard for Q1–Q7 + extra analytics, every number traceable | `lightdash/`, dbt metrics | ☑ (parity-tested via Lightdash API) |

## Deliverables
| # | Requirement | Where | Status |
|---|---|---|---|
| D1 | Document with ERM + answers + SQL + dashboard screenshots | `docs/ANSWERS.md` (+ exported doc) | ◐ (screenshots pending P6) |
| D2 | Git repo URL shared | GitHub | ☐ |
| D3a | README: run locally + cloud, no credentials | `README.md` | ☐ |
| D3b | Clean, readable code | lint + review | ☐ |
| D3c | CI/CD instructions | `README.md#ci-cd` | ☐ |
| D3d | Guardrail files committed where the agent expects them | `CLAUDE.md`, `.claude/` | ◐ |
| D3e | AI workflow document | `AI_WORKFLOW.md` | ◐ |
| D3f | Architecture diagram + design decisions/trade-offs | `docs/ARCHITECTURE.md`, `docs/decisions.md` | ☐ |
| D3g | Additional resources | `docs/` | ☐ |
| D4 | Dashboard running locally, access in README, screenshots | `README.md`, `docs/ANSWERS.md` | ◐ (screenshot in ANSWERS; README pending) |
| D5 | Cloud: read-only DB creds + dashboard URL (outside the repo) | delivered doc only | ☐ |

## Extras (our own scope)
| Item | Where | Status |
|---|---|---|
| Cube semantic layer generated from dbt | `semantic/cube/` | ☑ |
| Conversational analytics (Bedrock LLM over Cube, model chosen by bake-off) | `chat/`, `docs/bakeoff.md` | ◐ (gpt-oss 7/7; Claude pending access) |
| Lightdash ↔ Cube parity test | `tests/test_semantic_parity.py` | ☑ |
