-- Grain: one row per bar.
select
    bar_id,
    name as bar_name,
    address
from {{ ref('bar') }}
