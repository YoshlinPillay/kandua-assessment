-- Grain: one row per beverage. Source catalog + human-approved supplement rows (decision D-008).
with source as (
    select * from {{ source('juan_raw', 'beverages') }}
),

supplement as (
    select * from {{ ref('seed_beverage_catalog_supplement') }}
),

from_source as (
    select
        trim(name) as beverage_name,
        nullif(trim(codebar), '') as barcode,
        lower(trim(type)) as beverage_type,
        cast(alcohol_units as numeric(6, 2)) as alcohol_units,
        false as is_assumed
    from source
),

from_supplement as (
    select
        trim(name) as beverage_name,
        nullif(trim(codebar), '') as barcode,
        lower(trim(type)) as beverage_type,
        cast(alcohol_units as numeric(6, 2)) as alcohol_units,
        is_assumed
    from supplement
    -- If the source catalog ever gains this beverage, the source wins and the assumption drops out.
    where trim(name) not in (select from_source.beverage_name from from_source)
),

unioned as (
    select * from from_source
    union all
    select * from from_supplement
)

select * from unioned
