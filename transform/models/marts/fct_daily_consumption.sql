-- Grain: one row per calendar day from the first to the last day of data (zero-drinking days included).
-- Periodic snapshot fact for Q5 ("drunk" = a day with ≥ 14 units, D-015) and daily trends.
with daily as (
    select
        date_day,
        count(*) as visits,
        sum(servings) as servings,
        sum(alcohol_units) as alcohol_units
    from {{ ref('fct_visit') }}
    group by date_day
),

data_range as (
    select
        min(date_day) as first_day,
        max(date_day) as last_day
    from {{ ref('fct_visit') }}
)

select
    dim_date.date_day,
    coalesce(daily.visits, 0) as visits,
    coalesce(daily.servings, 0) as servings,
    coalesce(daily.alcohol_units, 0) as alcohol_units,
    coalesce(daily.alcohol_units, 0) >= {{ var('drunk_units_threshold') }} as is_drunk,
    dim_date.date_day > data_range.last_day - 30 as is_in_last_30_days_of_data
from {{ ref('dim_date') }} as dim_date
cross join data_range
left join daily on dim_date.date_day = daily.date_day
where dim_date.date_day between data_range.first_day and data_range.last_day
