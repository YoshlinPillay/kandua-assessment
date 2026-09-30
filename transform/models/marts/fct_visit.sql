-- Grain: one row per visit (D-006), including visits without a drink, with drink measures rolled up.
with visits as (
    select * from {{ ref('visit') }}
),

drink_totals as (
    select
        visit_id,
        count(*) as drink_lines,
        sum(quantity) as servings,
        sum(alcohol_units) as alcohol_units,
        sum(amount_paid) as amount_paid,
        sum(amount_saved) as amount_saved
    from {{ ref('fct_drink') }}
    group by visit_id
)

select
    visits.visit_id,
    visits.visited_on as date_day,
    visits.bar_id,
    drink_totals.visit_id is not null as has_drink,
    coalesce(drink_totals.drink_lines, 0) as drink_lines,
    coalesce(drink_totals.servings, 0) as servings,
    coalesce(drink_totals.alcohol_units, 0) as alcohol_units,
    coalesce(drink_totals.amount_paid, 0) as amount_paid,
    coalesce(drink_totals.amount_saved, 0) as amount_saved
from visits
left join drink_totals on visits.visit_id = drink_totals.visit_id
