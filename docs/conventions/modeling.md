# Data modeling conventions

## Layers (dbt)
| Layer | Schema | Materialization | Purpose | Rules |
|---|---|---|---|---|
| raw | `raw` | dlt tables | Exact copy of the source JSON as loaded by dlt | Never edited. dlt metadata columns (`_dlt_*`) are kept. |
| staging | `staging` | view | 1:1 with a raw table: rename, cast, trim, dedup | No joins across entities. Every cleaning rule has a comment and an entry in `docs/data_profile.md`. |
| core | `core` | table, **contract enforced** | Transactional model (3NF) implementing `docs/erm/transactional.dbml` | PK / FK / NOT NULL / UNIQUE declared as dbt constraints so Postgres enforces them. |
| marts | `marts` | table | Analytical star schema (Q9) | `fct_*` / `dim_*`. Metrics are defined here in YAML `meta` only. |

## Naming
- snake_case everywhere. Table names are **singular** in `core` (`bar`, `visit`) and prefixed in marts
  (`dim_bar`, `fct_drink`).
- Primary key column: `<table>_id`.
  - Keys must be **deterministic across runs**. Use the source's id when it provides a stable one, otherwise
    `dbt_utils.generate_surrogate_key(<natural key cols>)`. `row_number()` keys are not allowed because they
    change when the input changes.
  - Natural keys (e.g. beverage `barcode`) always carry a `UNIQUE` constraint.
- Foreign key column = referenced table's PK name (`visit.bar_id → bar.bar_id`).
- Booleans start with `is_`/`has_` (`is_happy_hour`). Timestamps end with `_at` (`visited_at`, UTC, `timestamptz`).
  Dates end with `_on` or `_date`.
- Money: `numeric(10,2)`, never float. Alcohol units: `numeric(6,2)`.

## Normalization (core)
- 1NF: atomic columns, no arrays/JSON in `core`, and every table has a PK.
- 2NF: no partial dependency on a composite key. Prefer single-column surrogate PKs, with UNIQUE on the
  natural composite key.
- 3NF: no transitive dependencies. Example: beverage type name lives in `beverage_type`, not repeated on `beverage`.
- Any deliberate denormalization in `core` must be written up in `docs/decisions.md`.

## UML → ERM mapping rules
- Associations with multiplicity `*` on one side become FKs on the many side.
- Generalization (Beverage → Beer/Tequila/Whiskey): the choice between a lookup/discriminator table and
  class-table inheritance is recorded in `docs/decisions.md` with the reasoning.
- Where the data contradicts the UML, the **data wins**, but the deviation must be documented.

## Marts (analytical)
- Grain is stated in the model description (e.g. "one row per drink line").
- Facts store additive measures (`quantity`, `alcohol_units`, `amount_paid`, `amount_saved`) precomputed
  once, so BI and Cube don't reimplement the arithmetic.
- `dim_date` is generated with `dbt_utils.date_spine`.
