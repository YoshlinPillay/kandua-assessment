-- Grain: one row per visit (D-006), including visits without a drink, with drink measures rolled up.
with visits as (
    select
        visit_id,
        bar_id,
        visited_on
    from {{ ref('visit') }}
),

-- grain: one row per visit that has at least one drink line
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
    cast(coalesce(drink_totals.drink_lines, 0) as integer) as drink_lines,
    cast(coalesce(drink_totals.servings, 0) as integer) as servings,
    cast(coalesce(drink_totals.alcohol_units, 0) as numeric(6, 2)) as alcohol_units,
    cast(coalesce(drink_totals.amount_paid, 0) as numeric(10, 2)) as amount_paid,
    cast(coalesce(drink_totals.amount_saved, 0) as numeric(10, 2)) as amount_saved
from visits
left join drink_totals on visits.visit_id = drink_totals.visit_id
