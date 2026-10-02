-- Grain: one row per calendar day from the first to the last visit date, zero-drinking days included.
-- The daily rollup behind Q5 ("drunk" = a day with ≥ 14 units, D-015) and the weekly NHS test (D-016).

-- grain: one row (the data's date range, taken from visits so no-drink days count)
{% set first_day = "(select min(visited_on) from " ~ ref('visit') ~ ")" %}
{% set day_after_last = "(select max(visited_on) + 1 from " ~ ref('visit') ~ ")" %}

with spine as (
    {{ dbt_utils.date_spine(datepart="day", start_date=first_day, end_date=day_after_last) }}
),

-- grain: one row per day with at least one visit
daily as (
    select
        visit.visited_on as date_day,
        count(*) as visits,
        sum(int_visit_drinks.servings) as servings,
        sum(int_visit_drinks.alcohol_units) as alcohol_units
    from {{ ref('visit') }} as visit
    left join {{ ref('int_visit_drinks') }} as int_visit_drinks on visit.visit_id = int_visit_drinks.visit_id
    group by visit.visited_on
)

select
    cast(spine.date_day as date) as date_day,
    cast(coalesce(daily.visits, 0) as integer) as visits,
    cast(coalesce(daily.servings, 0) as integer) as servings,
    cast(coalesce(daily.alcohol_units, 0) as numeric(6, 2)) as alcohol_units,
    coalesce(daily.alcohol_units, 0) >= {{ var('drunk_units_threshold') }} as is_drunk
from spine
left join daily on cast(spine.date_day as date) = daily.date_day
