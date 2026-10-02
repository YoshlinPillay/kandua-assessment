-- Grain: one row per visit (D-006), including visits without a drink, with drink measures rolled up.
with visits as (
    select
        visit_id,
        bar_id,
        visited_on
    from {{ ref('visit') }}
)

select
    visits.visit_id,
    visits.visited_on as date_day,
    visits.bar_id,
    int_visit_drinks.visit_id is not null as has_drink,
    cast(coalesce(int_visit_drinks.drink_lines, 0) as integer) as drink_lines,
    cast(coalesce(int_visit_drinks.servings, 0) as integer) as servings,
    cast(coalesce(int_visit_drinks.alcohol_units, 0) as numeric(6, 2)) as alcohol_units,
    cast(coalesce(int_visit_drinks.amount_paid, 0) as numeric(10, 2)) as amount_paid,
    cast(coalesce(int_visit_drinks.amount_saved, 0) as numeric(10, 2)) as amount_saved
from visits
left join {{ ref('int_visit_drinks') }} as int_visit_drinks on visits.visit_id = int_visit_drinks.visit_id
