with types as (
    select distinct beverage_type from {{ ref('stg_juan__beverages') }}
)

select
    cast({{ dbt_utils.generate_surrogate_key(['beverage_type']) }} as text) as beverage_type_id,
    cast(beverage_type as text) as name
from types
