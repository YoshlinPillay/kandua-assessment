-- One row per drink line. Visits without a drink (beverage is null) have no drink row.
-- Left joins so that an unmatched stock line fails the NOT NULL contract instead of disappearing.
with visits as (
    select * from {{ ref('stg_juan__visit_events') }}
    where beverage_name is not null
),

bars as (
    select * from {{ ref('bar') }}
),

beverages as (
    select * from {{ ref('beverage') }}
),

stock as (
    select * from {{ ref('stock') }}
)

select
    cast(
        {{ dbt_utils.generate_surrogate_key(['visits.visit_id', 'stock.stock_id', 'visits.is_happy_hour']) }}
        as text
    ) as drink_id,
    cast(visits.visit_id as uuid) as visit_id,
    cast(stock.stock_id as text) as stock_id,
    cast(visits.quantity as integer) as quantity,
    cast(visits.is_happy_hour as boolean) as is_happy_hour
from visits
left join bars on visits.bar_name = bars.name
left join beverages on visits.beverage_name = beverages.name
left join stock
    on
        bars.bar_id = stock.bar_id
        and beverages.beverage_id = stock.beverage_id
