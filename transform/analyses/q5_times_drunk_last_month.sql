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
