-- The raw load must match the counts recorded in docs/data_profile.md. A change means the source changed:
-- re-profile before trusting any answer.
with counts as (
    select
        'bars' as tbl,
        count(*) as n,
        5 as expected
    from {{ source('juan_raw', 'bars') }}
    union all
    select
        'bars__stock' as tbl,
        count(*) as n,
        29 as expected
    from {{ source('juan_raw', 'bars__stock') }}
    union all
    select
        'beverages' as tbl,
        count(*) as n,
        8 as expected
    from {{ source('juan_raw', 'beverages') }}
    union all
    select
        'visit_events' as tbl,
        count(*) as n,
        1000 as expected
    from {{ source('juan_raw', 'visit_events') }}
)

select * from counts
where n != expected
