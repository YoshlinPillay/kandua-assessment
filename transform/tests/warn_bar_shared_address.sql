-- D-009: bars whose addresses match after normalisation (Jerry's "5 Park Rd" / Fat Cactus "5 Park Road").
{{ config(severity='warn') }}
with normalised as (
    select
        name,
        regexp_replace(lower(address), '\mroad\M', 'rd', 'g') as address_key
    from {{ ref('bar') }}
)

select
    address_key,
    string_agg(name, ', ' order by name) as bars
from normalised
group by address_key
having count(*) > 1
