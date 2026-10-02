-- Grain: one row per ISO week (Monday start) from the first to the last week with data (D-016).
-- Weeks without drinking are present with 0 units, so averages aren't inflated. The first week is partial.
-- grain: one row per ISO week
select
    cast(date_trunc('week', date_day) as date) as iso_week_start,
    cast(count(*) as integer) as days_covered,
    cast(sum(servings) as integer) as servings,
    cast(sum(alcohol_units) as numeric(6, 2)) as alcohol_units,
    cast(count(*) filter (where is_drunk) as integer) as drunk_days,
    {{ var('nhs_weekly_units_limit') }} as nhs_weekly_limit,
    sum(alcohol_units) > {{ var('nhs_weekly_units_limit') }} as is_over_nhs_limit,
    count(*) < 7 as is_partial_week
from {{ ref('int_daily_consumption') }}
group by 1
