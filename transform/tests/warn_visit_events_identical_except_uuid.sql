-- D-007: identical-except-uuid events are kept on purpose; this only keeps them visible (7 pairs).
{{ config(severity='warn') }}
select
    bar_name,
    visited_on,
    beverage_name,
    quantity,
    is_happy_hour,
    count(*) as events
from {{ ref('stg_juan__visit_events') }}
group by bar_name, visited_on, beverage_name, quantity, is_happy_hour
having count(*) > 1
