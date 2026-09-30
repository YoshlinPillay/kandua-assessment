-- Grain: one row per (bar, beverage) price-list line.
with stock as (
    select * from {{ source('juan_raw', 'bars__stock') }}
),

bars as (
    select * from {{ ref('stg_juan__bars') }}
),

renamed as (
    select
        bars.bar_name,
        trim(stock.name) as beverage_name,
        cast(stock.price as numeric(10, 2)) as price
    from stock
    inner join bars on stock._dlt_parent_id = bars.bar_record_id
)

select * from renamed
