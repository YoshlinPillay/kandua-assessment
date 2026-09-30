select
    cast({{ dbt_utils.generate_surrogate_key(['name']) }} as text) as drinker_id,
    cast(name as text) as name
from {{ ref('seed_drinkers') }}
