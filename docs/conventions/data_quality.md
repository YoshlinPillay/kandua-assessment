# Data quality rules

Rules are enforced with dbt tests (`dbt build` fails on `error` severity) and Dagster asset checks. The
threshold for each rule is decided after profiling (P2) and written here.

## Mandatory tests per layer
| Layer | Tests |
|---|---|
| sources (`raw`) | `freshness` not applicable (static 2019 files). Row-count check: counts match the counts in the profiling report. |
| staging | `not_null` + `unique` on the entity's natural key **after** dedup. `accepted_values` on enumerations (beverage type). |
| core | Enforced contracts (PK/FK/NOT NULL/UNIQUE in Postgres) **plus** dbt `relationships` tests, so failures are reported and don't only crash the build. |
| marts | `unique` + `not_null` on the fact grain. Reconciliation: Σ `fct_drink.quantity` = Σ `core.drink.quantity`. |

## Value rules (validate against the profile, then encode)
- `quantity` > 0, integer.
- `price` > 0 (numeric). Happy-hour savings = 50% of the full `price` × `quantity`.
- `alcohol_unit` ≥ 0.
- `visited_at` within the data's observed range (no future dates, no pre-2000 dates).
- Every drink belongs to a visit. Every drink's beverage is stocked by the bar of that visit (stock
  integrity). If the data violates this, the profile says how many rows are affected and `docs/decisions.md`
  says what we did.

## Duplicates
- Exact duplicate raw records: dropped in staging. The count is recorded in the profile.
- Same natural key with conflicting attributes: **stop and ask the human**. Never pick a winner silently.

## Answer verification (anti-hallucination)
Each Q1–Q7 answer is computed twice, independently:
1. SQL in `transform/analyses/` against dbt models.
2. pandas in `tests/answers/` straight from the raw JSON files.

`pytest` asserts that the two agree. A number goes into the docs or dashboard only after both agree.
