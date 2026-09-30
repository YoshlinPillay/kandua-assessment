# Decision log

These are the architecture and interpretation decisions. **Decided by** says whether the human (Yoshlin) decided
or the agent proposed and the human approved. Interpretation decisions (Q1–Q7 semantics) are always made by
the human.

| ID | Date | Decision | Alternatives considered | Why | Decided by |
|---|---|---|---|---|---|
| D-001 | 2026-09-30 | Ingestion with **dlt** into Postgres `raw` | Custom Python loader, Meltano, Mage loaders | The brief says not to reinvent ingestion. dlt infers schemas, flattens nested JSON and adds load metadata. | Human (after agent explained dlt) |
| D-002 | 2026-09-30 | **Dagster** orchestration (`dagster-dlt`, `dagster-dbt`) | No orchestrator; Mage.ai | Asset-level lineage from raw JSON through dbt models to marts, plus asset checks. Mage overlaps with dlt and treats dbt as one block. | Human |
| D-003 | 2026-09-30 | **Lightdash** for dashboards, **Cube Core** for the conversational layer, metrics defined **once** in dbt YAML, Cube models generated with `cube_dbt`, CI parity test | Cube + Superset only; Lightdash only with a custom agent on its API | Lightdash's built-in AI agents need an enterprise licence. Cube's REST API is built for programmatic metric queries. Generating the models plus a parity test controls the drift risk of having two semantic layers. | Human |
| D-004 | 2026-09-30 | Hosting on **AWS only**: Terraform, RDS Postgres + one EC2 (compose), GH Actions OIDC | Render.com, self-hosted behind Caddy, ECS Fargate | Render free Postgres expires after 30 days and 512MB RAM is too small for Lightdash. Fargate adds cost and complexity for this size. The brief asks for read-only DB credentials, which RDS gives cleanly. | Human |
| D-005 | 2026-09-30 | Transactional tables built by dbt `core` models with **enforced contracts** (Postgres PK/FK constraints) | Hand-written DDL migrations + separate load step | One tool owns the schema. The constraints are real in Postgres, and the tests and docs sit next to the models. Trade-off: dbt rebuilds the tables on each run, which suits a batch analytics load but isn't how a live OLTP app would manage its schema. | Agent proposed, human approved |

## Interpretation decisions (Q1–Q7)
_Filled in during P5. Each entry lists the options with the number each produces and the option the human chose._
