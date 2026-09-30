-- Grain: one row per visit event = one visit (decision D-006). No dedup (decision D-007).
with source as (
    select * from {{ source('juan_raw', 'visit_events') }}
),

renamed as (
    select
        cast(uuid as uuid) as visit_id,
        trim(bar_name) as bar_name,
        cast(visited as date) as visited_on,
        trim(beverage) as beverage_name,
        cast(drinks as integer) as quantity,
        happy_hour as is_happy_hour
    from source
)

select * from renamed
