-- Grain: one row per ISO week (Monday start) from the first to the last week with data (D-016).
-- Weeks without drinking are present with 0 units, so averages aren't inflated. The first week is partial.
with daily as (
    select
        dim_date.iso_week_start,
        fct_daily_consumption.date_day,
        fct_daily_consumption.servings,
        fct_daily_consumption.alcohol_units,
        fct_daily_consumption.is_drunk
    from {{ ref('fct_daily_consumption') }} as fct_daily_consumption
    inner join {{ ref('dim_date') }} as dim_date on fct_daily_consumption.date_day = dim_date.date_day
)

select
    iso_week_start,
    count(*) as days_covered,
    sum(servings) as servings,
    sum(alcohol_units) as alcohol_units,
    count(*) filter (where is_drunk) as drunk_days,
    {{ var('nhs_weekly_units_limit') }} as nhs_weekly_limit,
    sum(alcohol_units) > {{ var('nhs_weekly_units_limit') }} as is_over_nhs_limit,
    count(*) < 7 as is_partial_week
from daily
group by iso_week_start
