-- One row per visit event (decision D-006). Every visit belongs to Juan (decision C7).
with visits as (
    select * from {{ ref('stg_juan__visit_events') }}
),

bars as (
    select * from {{ ref('bar') }}
),

juan as (
    select drinker_id from {{ ref('drinker') }}
    where name = 'Juan'
)

select
    cast(visits.visit_id as uuid) as visit_id,
    cast(juan.drinker_id as text) as drinker_id,
    cast(bars.bar_id as text) as bar_id,
    cast(visits.visited_on as date) as visited_on
from visits
cross join juan
left join bars on visits.bar_name = bars.name
