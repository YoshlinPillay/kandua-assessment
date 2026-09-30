with beverages as (
    select * from {{ ref('stg_juan__beverages') }}
),

beverage_types as (
    select * from {{ ref('beverage_type') }}
)

select
    cast({{ dbt_utils.generate_surrogate_key(['beverages.beverage_name']) }} as text) as beverage_id,
    cast(beverage_types.beverage_type_id as text) as beverage_type_id,
    cast(beverages.beverage_name as text) as name,
    cast(beverages.barcode as text) as barcode,
    cast(beverages.alcohol_units as numeric(6, 2)) as alcohol_units,
    cast(beverages.is_assumed as boolean) as is_assumed
from beverages
left join beverage_types on beverages.beverage_type = beverage_types.name
