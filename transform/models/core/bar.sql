select
    cast({{ dbt_utils.generate_surrogate_key(['bar_name']) }} as text) as bar_id,
    cast(bar_name as text) as name,
    cast(address as text) as address
from {{ ref('stg_juan__bars') }}
