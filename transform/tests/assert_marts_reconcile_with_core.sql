-- The star schema must tell the same story as the transactional model: same visits, servings and units,
-- and paid + saved = full price on every drink line. Returns a row per failed check.
with checks as (
    select
        'visits' as metric,
        (select count(*) from {{ ref('fct_visit') }}) as marts_value,
        (select count(*) from {{ ref('visit') }}) as core_value
    union all
    select
        'servings' as metric,
        (select sum(quantity) from {{ ref('fct_drink') }}) as marts_value,
        (select sum(quantity) from {{ ref('drink') }}) as core_value
    union all
    select
        'daily_units_vs_drink_units' as metric,
        (select sum(alcohol_units) from {{ ref('fct_daily_consumption') }}) as marts_value,
        (select sum(alcohol_units) from {{ ref('fct_drink') }}) as core_value
    union all
    select
        'weekly_units_vs_daily_units' as metric,
        (select sum(alcohol_units) from {{ ref('fct_weekly_consumption') }}) as marts_value,
        (select sum(alcohol_units) from {{ ref('fct_daily_consumption') }}) as core_value
    union all
    select
        'lines_where_paid_plus_saved_not_full' as metric,
        (
            select count(*) from {{ ref('fct_drink') }}
            where amount_paid + amount_saved != full_price_amount
        ) as marts_value,
        0 as core_value
)

select * from checks
where marts_value != core_value
