-- Q5: Based on alcohol units and number of drinks, how many times has Juan been drunk in the last month?
-- Interpretation (D-014, D-015):
--   * "last month" = the last 30 days of data, ending on the latest visit date (2019-09-22).
--   * "drunk" = a calendar day on which Σ(quantity × alcohol_units) over all visits that day ≥ 14.
-- Expected result shape: exactly 30 rows, one per day in the window (0 units on days without drinking),
-- with is_drunk and the window total times_drunk (0 if no day qualifies).

-- grain: one row per day with at least one drink
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

-- grain: one row per day of the 30-day window ending on the last visit date
window_days as (
    select generate_series(max(visited_on) - 29, max(visited_on), interval '1 day')::date as visited_on
    from {{ ref('visit') }}
)

select
    window_days.visited_on,
    coalesce(daily_units.alcohol_units, 0) as alcohol_units,
    coalesce(daily_units.alcohol_units, 0) >= 14 as is_drunk,
    count(*) filter (where daily_units.alcohol_units >= 14) over () as times_drunk
from window_days
left join daily_units on window_days.visited_on = daily_units.visited_on
order by window_days.visited_on
