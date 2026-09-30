-- Q6: The NHS recommends no more than 14 units per week. Is Juan an alcoholic?
-- Interpretation (D-016): ISO weeks (Monday start) from the first to the last week of data. Weeks without any
-- drinking count as 0 (generated, not skipped). The first week is partial (data starts Wed 2018-01-03).
-- Headline = average units per week vs 14. Supporting = share of weeks over 14.
-- Expected result shape: one row: weeks, weeks_over_limit, avg_units_per_week, max_units_in_a_week, verdict.

-- grain: one row per ISO week with at least one drink
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

-- grain: one row per ISO week from the first to the last *visit* (not drink), so the range doesn't depend
-- on whether the first/last visits had drinks
all_weeks as (
    select
        generate_series(
            date_trunc('week', min(visited_on)), date_trunc('week', max(visited_on)), interval '1 week'
        )::date as week_start
    from {{ ref('visit') }}
),

weeks as (
    select
        all_weeks.week_start,
        coalesce(weekly_units.alcohol_units, 0) as alcohol_units
    from all_weeks
    left join weekly_units on all_weeks.week_start = weekly_units.week_start
)

-- grain: one row (all weeks)
select
    count(*) as weeks,
    count(*) filter (where alcohol_units > 14) as weeks_over_limit,
    round(avg(alcohol_units), 2) as avg_units_per_week,
    max(alcohol_units) as max_units_in_a_week,
    case when avg(alcohol_units) > 14 then 'Yes' else 'No' end as exceeds_nhs_guidance
from weeks
