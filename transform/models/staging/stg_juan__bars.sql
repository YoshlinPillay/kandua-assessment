with source as (
    select * from {{ source('juan_raw', 'bars') }}
),

renamed as (
    select
        _dlt_id as bar_record_id,
        trim(bar_name) as bar_name,
        trim(address) as address
    from source
)

select * from renamed
