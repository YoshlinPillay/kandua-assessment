-- Grain: one row per calendar day, covering the full calendar years in which visits occur
-- (so days without drinking exist too). Built with dbt_utils.date_spine (modeling.md).
{% set start_date = "(select date_trunc('year', min(visited_on))::date from " ~ ref('visit') ~ ")" %}
{% set end_date = "(select (date_trunc('year', max(visited_on)) + interval '1 year')::date from "
    ~ ref('visit') ~ ")" %}

with spine as (
    {{ dbt_utils.date_spine(datepart="day", start_date=start_date, end_date=end_date) }}
)

select
    date_day::date as date_day,
    date_trunc('week', date_day)::date as iso_week_start,
    date_trunc('month', date_day)::date as month_start,
    extract(isoyear from date_day)::integer as iso_year,
    extract(week from date_day)::integer as iso_week,
    extract(year from date_day)::integer as calendar_year,
    extract(month from date_day)::integer as calendar_month,
    trim(to_char(date_day, 'Day')) as day_name,
    extract(isodow from date_day)::integer as iso_day_of_week,
    extract(isodow from date_day) in (6, 7) as is_weekend
from spine
