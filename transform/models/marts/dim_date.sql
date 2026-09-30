-- Grain: one row per calendar day, covering the whole range of visits (so days without drinking exist too).
with bounds as (
    select
        date_trunc('year', min(visited_on))::date as first_day,
        (date_trunc('year', max(visited_on)) + interval '1 year - 1 day')::date as last_day
    from {{ ref('visit') }}
),

days as (
    select generate_series(bounds.first_day, bounds.last_day, interval '1 day')::date as date_day
    from bounds
)

select
    date_day,
    date_trunc('week', date_day)::date as iso_week_start,
    date_trunc('month', date_day)::date as month_start,
    extract(isoyear from date_day)::integer as iso_year,
    extract(week from date_day)::integer as iso_week,
    extract(year from date_day)::integer as calendar_year,
    extract(month from date_day)::integer as calendar_month,
    trim(to_char(date_day, 'Day')) as day_name,
    extract(isodow from date_day)::integer as iso_day_of_week,
    extract(isodow from date_day) in (6, 7) as is_weekend
from days
