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

| D-006 | 2026-09-30 | **Each visit event = one visit** (uuid = visit id) | Visit = (bar, date) | No time signal exists: the dates have no time, the uuids are v4 (random) and the file order is random. Reading (bar, date) as the visit would contradict 28 groups that contain both a no-drink and a drink event. | Human (after agent showed examples + impact: Q4 104 vs 74) |
| D-007 | 2026-09-30 | Keep 7 identical-except-uuid event pairs | Drop one of each pair | Distinct source ids. Same-day repeats are common (129 bar-days have more than one event). | Human |
| D-008 | 2026-09-30 | Tiger's Milk Lager = beer, 1.2 units, assumed (seed with `is_assumed`) | Exclude from unit-based answers | A lager is a beer, and every catalog beer is 1.2 units. | Human |
| D-009 | 2026-09-30 | Surrogate keys. Barcode non-unique. Shared bar address kept and flagged. | Null out Don Julio's barcode | Don't silently change source data. Warn-level tests keep the collision visible. | Human |
| D-010 | 2026-09-30 | Beverage inheritance mapped to a `beverage_type` lookup table | Single table with a text discriminator; class-table inheritance (beer/tequila/whiskey tables) | The subclasses have no own attributes, so subtype tables would be empty 1:1 extensions. A lookup table keeps the type names in one place (3NF) and adding a type is a row, not a migration. | Agent proposed, pending human approval |
| D-011 | 2026-09-30 | Drink→stock same-bar invariant as a dbt test, not a composite FK | Carry `bar_id` on `drink` with composite FKs to `visit` and `stock` | A composite FK needs a transitive dependency (drink→visit→bar), which breaks 3NF. The test gives the same guarantee for a batch-loaded model. | Agent proposed, pending human approval |
| D-012 | 2026-09-30 | `Juan` generalized to a `drinker` table | No table (implicit single user) | The UML has Juan as a class with a 0..* association. A one-row table keeps the FK explicit and lets the app support more users. | Agent proposed, pending human approval |

## Interpretation decisions (Q1–Q7)
_Filled in during P5. Each entry lists the options with the number each produces and the option the human chose._
