-- Nothing may be lost between staging and core: visits, drink lines and servings must all reconcile.
with stg as (
    select
        count(*) as visits,
        count(beverage_name) as drink_lines,
        coalesce(sum(quantity), 0) as servings
    from {{ ref('stg_juan__visit_events') }}
),

core as (
    select
        (select count(*) from {{ ref('visit') }}) as visits,
        (select count(*) from {{ ref('drink') }}) as drink_lines,
        (select coalesce(sum(quantity), 0) from {{ ref('drink') }}) as servings
)

select
    stg.*,
    core.*
from stg cross join core
where
    stg.visits != core.visits
    or stg.drink_lines != core.drink_lines
    or stg.servings != core.servings
