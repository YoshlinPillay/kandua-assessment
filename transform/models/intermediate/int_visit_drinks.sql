-- Grain: one row per visit that has at least one drink line, with its drink measures rolled up.
-- Visits without a drink are absent here; fct_visit and int_daily_consumption left-join to core.visit.
select
    visit_id,
    count(*) as drink_lines,
    sum(quantity) as servings,
    sum(alcohol_units) as alcohol_units,
    sum(amount_paid) as amount_paid,
    sum(amount_saved) as amount_saved
from {{ ref('int_drink_lines') }}
group by visit_id
