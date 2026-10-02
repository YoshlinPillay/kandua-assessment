-- Grain: one row per calendar day from the first to the last day of data (zero-drinking days included).
-- Periodic snapshot fact for Q5 ("drunk" = a day with ≥ 14 units, D-015) and daily trends.
select
    date_day,
    visits,
    servings,
    alcohol_units,
    is_drunk,
    date_day > max(date_day) over () - 30 as is_in_last_30_days_of_data
from {{ ref('int_daily_consumption') }}
