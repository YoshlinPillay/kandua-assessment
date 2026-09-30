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
| D-010 | 2026-09-30 | Beverage inheritance mapped to a `beverage_type` lookup table | Single table with a text discriminator; class-table inheritance (beer/tequila/whiskey tables) | The subclasses have no own attributes, so subtype tables would be empty 1:1 extensions. A lookup table keeps the type names in one place (3NF) and adding a type is a row, not a migration. | Agent proposed, human approved |
| D-011 | 2026-09-30 | Drink→stock same-bar invariant as a dbt test, not a composite FK | Carry `bar_id` on `drink` with composite FKs to `visit` and `stock` | A composite FK needs a transitive dependency (drink→visit→bar), which breaks 3NF. The test gives the same guarantee for a batch-loaded model. | Agent proposed, human approved |
| D-012 | 2026-09-30 | `Juan` generalized to a `drinker` table | No table (implicit single user) | The UML has Juan as a class with a 0..* association. A one-row table keeps the FK explicit and lets the app support more users. | Agent proposed, human approved |
| D-013 | 2026-09-30 | Q2 counts all visits in `core.visit` (no join to `drink`) and the SQL returns a ranked list | Count only visits with drinks (Jerry's would win) | Consistent with D-006 and Q4 (a visit without a drink is still a visit). The ranked output makes the 1-visit margin visible. | Agent proposed after reviewer finding; implemented in Q2 SQL (human to confirm at P5 checkpoint) |

## Interpretation decisions (Q1–Q7)
Each entry lists the options with the number each one produces, and the option the human chose.

| ID | Q | Decision (chosen) | Options → result | Decided by |
|---|---|---|---|---|
| D-014 | Q5 | "Last month" = **the last 30 days of data** (2019-08-24 → 2019-09-22) | Last 30 days → **1** · Aug-2019 (last full month) → 1 · Sep-2019 month-to-date → 0 | Human |
| D-015 | Q5 | "Drunk" = a **calendar day** with Σ units ≥ 14 across all visits | Per day → 1 · per visit → 0 (the most in one visit is 6.0 units) | Human |
| D-016 | Q6 | Weekly test = **both views on ISO weeks**. Headline is the average per week; the share of weeks over 14 supports it. Zero-drinking weeks count as 0. | Average 33.24 units/week vs 14 · 87/90 ISO weeks over 14 (88/91 with Sunday-start weeks) | Human |
| D-017 | Q6 | Verdict worded **"Yes, Juan is an alcoholic"** by the brief's NHS criterion | Softer wording: "consistently exceeds NHS guidance" (not a clinical diagnosis) | Human |
| D-018 | Q1, Q3 | "Drinks the most" / "favourite" = **most servings** (Σ quantity) | Servings, drink lines and units all give the same winners (beer; Castle Lite), so the choice doesn't change the answer | Agent, disclosed in the SQL output |
| D-019 | Q7 | Savings = Σ 0.5 × stock price × quantity over happy-hour drinks. Prices are ZAR (Cape Town); the source has no currency. | — | Brief + agent assumption on currency |
