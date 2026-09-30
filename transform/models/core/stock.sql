-- Left joins on purpose: an unmatched bar/beverage yields a null FK, which the NOT NULL contract rejects
-- loudly instead of an inner join silently dropping the line.
with stock_lines as (
    select * from {{ ref('stg_juan__bar_stock') }}
),

bars as (
    select * from {{ ref('bar') }}
),

beverages as (
    select * from {{ ref('beverage') }}
)

select
    cast(
        {{ dbt_utils.generate_surrogate_key(['stock_lines.bar_name', 'stock_lines.beverage_name']) }} as text
    )
        as stock_id,
    cast(bars.bar_id as text) as bar_id,
    cast(beverages.beverage_id as text) as beverage_id,
    cast(stock_lines.price as numeric(10, 2)) as price
from stock_lines
left join bars on stock_lines.bar_name = bars.name
left join beverages on stock_lines.beverage_name = beverages.name
