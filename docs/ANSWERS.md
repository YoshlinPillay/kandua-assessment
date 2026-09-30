# Answers — Juan the Drinker

Every number below was computed twice: by the SQL shown (run against the 3NF `core` schema) and independently
with pandas straight from the raw JSON (`tests/answers/reference.py`). `make test` asserts they are equal, and
also that the star schema (`marts`, the dashboard's source) reproduces them. Interpretation choices were made
by the human and are recorded in [`decisions.md`](decisions.md). Data covers **2018-01-03 → 2019-09-22**:
1,000 visits, 896 drink lines, 5 bars, 9 beverages.

| # | Question | Answer |
|---|---|---|
| Q1 | Beverage type Juan drinks the most | **Beer**: 1,595 servings (tequila 513, whiskey 257) |
| Q2 | Bar Juan visits the most | **Yours Truly**: 207 visits (Jerry's 206, a 1-visit margin) |
| Q3 | Favourite beer brand | **Castle Lite**: 754 servings (next: Tiger's Milk Lager 268) |
| Q4 | Visits without a drink | **104** of 1,000 visits |
| Q5 | Times drunk in the last month (≥14 units) | **1** (2019-08-31, 14.8 units) |
| Q6 | Alcoholic by the NHS 14 units/week guideline? | **Yes**: 33.24 units/week on average; over the limit in 87 of 90 weeks |
| Q7 | Money saved on happy hours (50% off) | **R 21,587.05** (paid R 21,587.05 for R 43,174.10 of drinks at full price) |

## ERM (transactional model)

The source of truth is [`erm/transactional.dbml`](erm/transactional.dbml). The diagram and the UML → ERM mapping
are in [`erm/README.md`](erm/README.md).

```
drinker ─< visit >─ bar ─< stock >─ beverage >─ beverage_type
              └────< drink >────┘
```

---

## Q1: What is the beverage type that Juan drinks the most?
**Beer.** It wins by servings (1,595), by drink lines (535) and by alcohol units (1,914), so the answer
doesn't depend on how "most" is read (D-018). It includes 268 servings of Tiger's Milk Lager, treated as a beer
(D-008). Without them, beer still wins with 1,327.

```sql
-- Q1: What is the beverage type that Juan drinks the most?
-- Interpretation: most servings (sum of drink quantity). Drink lines and alcohol units are shown too, so
-- the answer can be checked under every reasonable reading. Tiger's Milk Lager = beer (D-008).
-- Expected result shape: one row per beverage type, ranked by servings.
with drinks as (
    select
        beverage_type.name as beverage_type,
        drink.quantity,
        drink.quantity * beverage.alcohol_units as alcohol_units
    from {{ ref('drink') }} as drink
    inner join {{ ref('stock') }} as stock on drink.stock_id = stock.stock_id
    inner join {{ ref('beverage') }} as beverage on stock.beverage_id = beverage.beverage_id
    inner join {{ ref('beverage_type') }} as beverage_type
        on beverage.beverage_type_id = beverage_type.beverage_type_id
)

select
    beverage_type,
    sum(quantity) as servings,
    count(*) as drink_lines,
    sum(alcohol_units) as alcohol_units,
    rank() over (order by sum(quantity) desc) as servings_rank
from drinks
group by beverage_type
order by servings_rank
```

## Q2: What is the bar Juan visits the most?
**Yours Truly, with 207 visits.** Jerry's has 206. The query ranks every bar so the thin margin is visible.

Sensitivity (see `data_profile.md`): counting one visit per (bar, date) gives Yours Truly 181 vs Jerry's 177.
Counting **only visits with a drink** gives Jerry's (191). We count all visits, consistent with Q4, because a
visit without a drink is still a visit (D-013).

```sql
-- Q2: What is the bar Juan visits the most?
-- Interpretation: count every visit in core.visit, including visits without a drink (D-006, D-013).
-- No join to drink: counting only visits with a drink would change the winner. The full ranking is
-- returned because the margin is one visit.
-- Expected result shape: one row per bar with visits and rank.
select
    bar.name as bar_name,
    count(*) as visits,
    rank() over (order by count(*) desc) as visits_rank
from {{ ref('visit') }} as visit
inner join {{ ref('bar') }} as bar on visit.bar_id = bar.bar_id
group by bar.name
order by visits_rank, bar_name
```

## Q3: What is Juan's favourite beer brand?
**Castle Lite: 754 servings over 262 drink lines**, far ahead of Tiger's Milk Lager (268). "Black Label" is
counted as a beer, because it's Carling Black Label (C6).

```sql
-- Q3: What is Juan's favourite beer brand?
-- Interpretation: the beer with the most servings. Black Label is a beer (Carling, C6).
-- Tiger's Milk Lager is an assumed beer (D-008).
-- Expected result shape: one row per beer, ranked by servings.
select
    beverage.name as beer,
    sum(drink.quantity) as servings,
    count(*) as drink_lines,
    rank() over (order by sum(drink.quantity) desc) as servings_rank
from {{ ref('drink') }} as drink
inner join {{ ref('stock') }} as stock on drink.stock_id = stock.stock_id
inner join {{ ref('beverage') }} as beverage on stock.beverage_id = beverage.beverage_id
inner join {{ ref('beverage_type') }} as beverage_type
    on beverage.beverage_type_id = beverage_type.beverage_type_id
where beverage_type.name = 'beer'
group by beverage.name
order by servings_rank, beer
```

## Q4: How many times did Juan visit a bar and not have a drink?
**104 times.** Each source event is one visit (D-006). If a visit were defined as a (bar, date), the answer
would be 74.

```sql
-- Q4: How many times did Juan visit a bar and not have a drink?
-- Interpretation: visits (one per source event, D-006) with no drink line. Duplicate-looking events are kept
-- (D-007). The (bar, date) reading gives 74 and is reported as a sensitivity in docs/ANSWERS.md.
-- Expected result shape: one row: visits_without_drink, total_visits.
select
    count(*) filter (
        where not exists (
            select 1 from {{ ref('drink') }} as drink
            where drink.visit_id = visit.visit_id
        )
    ) as visits_without_drink,
    count(*) as total_visits
from {{ ref('visit') }} as visit
```

## Q5: How many times has Juan been drunk in the last month?
**Once: on 2019-08-31, with 14.8 units**, a three-bar night: 5 Tiger's Milk Lagers at Tiger's Milk (6.0), 2 Jose Cuervos at Cubana (2.8) and 5 Coronas at Jerry's (6.0). Without the Tiger's Milk Lager assumption (D-008) that day would be 8.8 units and the answer would be 0.

- "Last month" is the **last 30 days of data**, 2019-08-24 → 2019-09-22 (D-014). The data ends in 2019, so
  "today" would give zero data.
- "Drunk" means a **calendar day** with ≥ 14 units summed across all visits (D-015). No single visit ever
  reaches 14 (the most is 6.0).
- Sensitivity: Aug-2019 gives 1; Sep-2019 month-to-date gives 0.

```sql
-- Q5: Based on alcohol units and number of drinks, how many times has Juan been drunk in the last month?
-- Interpretation (D-014, D-015):
--   * "last month" = the last 30 days of data, ending on the latest visit date (2019-09-22).
--   * "drunk" = a calendar day on which Σ(quantity × alcohol_units) over all visits that day ≥ 14.
-- Expected result shape: one row per day in the window with units, plus is_drunk.
with daily_units as (
    select
        visit.visited_on,
        sum(drink.quantity * beverage.alcohol_units) as alcohol_units
    from {{ ref('drink') }} as drink
    inner join {{ ref('visit') }} as visit on drink.visit_id = visit.visit_id
    inner join {{ ref('stock') }} as stock on drink.stock_id = stock.stock_id
    inner join {{ ref('beverage') }} as beverage on stock.beverage_id = beverage.beverage_id
    group by visit.visited_on
),

data_end as (
    select max(visited_on) as last_day from {{ ref('visit') }}
)

select
    daily_units.visited_on,
    daily_units.alcohol_units,
    daily_units.alcohol_units >= 14 as is_drunk,
    count(*) filter (where daily_units.alcohol_units >= 14) over () as times_drunk
from daily_units
cross join data_end
where daily_units.visited_on > data_end.last_day - 30
order by daily_units.visited_on
```

## Q6: NHS recommends ≤ 14 units per week. Is Juan an alcoholic?
**Yes, by the brief's NHS criterion.** Juan averages **33.24 units per week**, 2.4× the limit. He exceeded 14
units in **87 of 90** ISO weeks, and his heaviest week reached 59.6 units. Weeks without drinking count as 0,
and the first week is partial (D-016, D-017).

```sql
-- Q6: The NHS recommends no more than 14 units per week. Is Juan an alcoholic?
-- Interpretation (D-016): ISO weeks (Monday start) from the first to the last week of data. Weeks without any
-- drinking count as 0 (generated, not skipped). The first week is partial (data starts Wed 2018-01-03).
-- Headline = average units per week vs 14. Supporting = share of weeks over 14.
-- Expected result shape: one row: weeks, weeks_over_limit, avg_units_per_week, max_units_in_a_week, verdict.
with weekly_units as (
    select
        date_trunc('week', visit.visited_on)::date as week_start,
        sum(drink.quantity * beverage.alcohol_units) as alcohol_units
    from {{ ref('drink') }} as drink
    inner join {{ ref('visit') }} as visit on drink.visit_id = visit.visit_id
    inner join {{ ref('stock') }} as stock on drink.stock_id = stock.stock_id
    inner join {{ ref('beverage') }} as beverage on stock.beverage_id = beverage.beverage_id
    group by 1
),

all_weeks as (
    select generate_series(min(week_start), max(week_start), interval '1 week')::date as week_start
    from weekly_units
),

weeks as (
    select
        all_weeks.week_start,
        coalesce(weekly_units.alcohol_units, 0) as alcohol_units
    from all_weeks
    left join weekly_units on all_weeks.week_start = weekly_units.week_start
)

select
    count(*) as weeks,
    count(*) filter (where alcohol_units > 14) as weeks_over_limit,
    round(avg(alcohol_units), 2) as avg_units_per_week,
    max(alcohol_units) as max_units_in_a_week,
    case when avg(alcohol_units) > 14 then 'Yes' else 'No' end as exceeds_nhs_guidance
from weeks
```

## Q7: How much money has Juan saved by drinking on Happy Hours?
**R 21,587.05.** 470 happy-hour drink lines (1,267 servings) worth R 43,174.10 at full price. Juan paid half.
Prices are assumed to be ZAR, because the bars are in Cape Town and the source doesn't state a currency (D-019).

```sql
-- Q7: How much money has Juan saved by drinking during Happy Hours (always a 50% discount)?
-- Interpretation: stock.price is the full price. A happy-hour drink costs 50% of it, so the saving per line
-- = 0.5 × price × quantity. Currency: ZAR (Cape Town bars; not stated in the source).
-- Expected result shape: one row: happy-hour lines, servings, full-price value, amount paid, amount saved.
select
    count(*) as happy_hour_drink_lines,
    sum(drink.quantity) as happy_hour_servings,
    round(sum(stock.price * drink.quantity), 2) as full_price_value,
    round(sum(stock.price * drink.quantity) - sum(stock.price * drink.quantity * 0.5), 2) as amount_paid,
    round(sum(stock.price * drink.quantity * 0.5), 2) as amount_saved
from {{ ref('drink') }} as drink
inner join {{ ref('stock') }} as stock on drink.stock_id = stock.stock_id
where drink.is_happy_hour
```

---

## Q8: Does the transactional model respect 1NF, 2NF and 3NF?
**Yes, and BCNF as well.**

- **1NF.** Every column is atomic and every table has a primary key.
  - The source's repeating group (`bars[].stock[]`, a JSON array) is unnested into its own `stock` table.
  - There are no lists, JSON or multi-valued columns in `core`.
- **2NF.** Every table has a single-column primary key, so there's nothing for a partial dependency to depend
  on. Where a composite natural key exists, the non-key attributes depend on the **whole** key:
  - `stock.price` depends on the pair (bar, beverage), not on either one alone.
  - `drink` is unique on (visit, stock, happy hour).
- **3NF.** No non-key attribute depends on another non-key attribute:
  - The beverage type's name lives only in `beverage_type`; `beverage` holds just the FK.
  - A bar's address lives only in `bar`.
  - `drink` stores neither `price` (it's reached through `stock`) nor `bar_id` (it's reached through `visit`).
    We kept `bar_id` out even though a composite FK carrying it would let Postgres enforce "the drink's stock
    belongs to the visit's bar". That rule is a data test instead (D-011).
- **BCNF.** The only determinants are candidate keys: the surrogate id and `name` in `bar` / `beverage` /
  `beverage_type`, and (bar, beverage) in `stock`. `barcode` is *not* a candidate key because the source
  reuses one (D-009).

Trade-offs worth naming:
- `drink` references the bar's *current* price through `stock`. In a live app where prices change, you would
  also store the price paid on the drink line (a fact about the sale, which doesn't violate 3NF). The source
  has one price per (bar, beverage), so we don't need it.
- `alcohol_units` is per beverage. In this data it happens to be constant per type, but that is a
  coincidence, not a dependency.

## Q9: What changes would you make for analytics?
**A Kimball star schema, built by dbt from the 3NF core** into schema `marts`. It's implemented, tested, and
is the dashboard's source. See [`erm/analytical.dbml`](erm/analytical.dbml).

| Model | Type | Grain | Why |
|---|---|---|---|
| `fct_drink` | transaction fact | one drink line | Precomputed additive measures (`alcohol_units`, `full_price_amount`, `amount_paid`, `amount_saved`), so BI only sums and never re-implements the arithmetic |
| `fct_visit` | accumulating fact | one visit (incl. no-drink visits) | Q2/Q4 and visit-level behaviour without joining drinks |
| `fct_daily_consumption` | periodic snapshot | one day, **zero days included** | Q5 ("drunk" days) and trends. Zero days make averages honest. |
| `fct_weekly_consumption` | periodic snapshot | one ISO week, zero weeks included | Q6 NHS test directly |
| `dim_date` | conformed dimension | one day | Week, month and weekday slicing |
| `dim_bar`, `dim_beverage` | dimensions | one bar / beverage | The beverage type is folded in, so it's one join from the fact |

Other changes for an analytical platform:
- **Capture time.** `visited_on` is only a date today. A timestamp would allow sessions, time of day and a real
  happy-hour window.
- **Store the price paid on the transaction.**
- **Slowly changing dimensions.** If prices or bar details change, use type-2 history (dbt snapshots) on
  `stock` and `bar`.
- **A semantic layer.** Metrics are defined once in dbt YAML and served to Lightdash and Cube (P6).
- **Columnar storage at scale.** DuckDB or a warehouse like Redshift/BigQuery instead of row-store Postgres.
  At 1,000 rows Postgres is the right call.

## Q10: Does the analytical model respect the normal forms?
**No, deliberately.** It satisfies 1NF and 2NF but **not 3NF**.

- **1NF: yes.** All values are atomic, and each table has a key (`drink_id`, `visit_id`, `date_day`, `iso_week_start`, …).
- **2NF: yes.** Every key is a single column, so partial dependencies can't exist.
- **3NF: no.** It contains transitive dependencies and derived data by design:
  - `dim_beverage.beverage_type` depends on the type, not on the beverage key (it's folded in from `beverage_type`).
  - `fct_drink.date_day` and `bar_id` depend on `visit_id`, and `unit_price` depends on (bar, beverage).
  - `alcohol_units`, `amount_paid` and `amount_saved` are derived from other columns.
  - `fct_visit`, `fct_daily_consumption` and `fct_weekly_consumption` are aggregates of `fct_drink`.

**Why that's acceptable here.** Normalization protects against update anomalies when many writers change
data. The marts have **one writer**: dbt rebuilds them from the 3NF core on every run, so redundancy can't
drift. Reconciliation tests assert that the marts equal the core (`assert_marts_reconcile_with_core`), and
`tests/answers/test_marts_match_answers.py` checks that they reproduce Q1–Q7. In exchange, analysts and BI
tools get fewer joins, precomputed additive measures and simple, fast queries. This is the usual OLTP (3NF)
vs OLAP (star) trade-off.

## Dashboard
_Screenshots are added in P6 (Lightdash)._
