-- Grain: one row per drink line, enriched with its visit, beverage and money/unit arithmetic.
-- All money and unit arithmetic happens here once. fct_drink publishes it, and the visit and daily rollups
-- aggregate it, so every fact reconciles to the same per-line amounts.
with drinks as (
    select
        drink_id,
        visit_id,
        stock_id,
        quantity,
        is_happy_hour
    from {{ ref('drink') }}
),

visits as (
    select
        visit_id,
        bar_id,
        visited_on
    from {{ ref('visit') }}
),

stock as (
    select
        stock_id,
        beverage_id,
        price
    from {{ ref('stock') }}
),

beverages as (
    select
        beverage_id,
        alcohol_units
    from {{ ref('beverage') }}
),

priced as (
    select
        drinks.drink_id,
        drinks.visit_id,
        visits.visited_on as date_day,
        visits.bar_id,
        stock.beverage_id,
        drinks.is_happy_hour,
        drinks.quantity,
        stock.price as unit_price,
        drinks.quantity * beverages.alcohol_units as alcohol_units,
        stock.price * drinks.quantity as full_price_amount,
        case when drinks.is_happy_hour then stock.price * drinks.quantity * 0.5 else 0 end as amount_saved
    from drinks
    inner join visits on drinks.visit_id = visits.visit_id
    inner join stock on drinks.stock_id = stock.stock_id
    inner join beverages on stock.beverage_id = beverages.beverage_id
)

-- Money is rounded per drink line to numeric(10,2) (D-022). The saving is rounded, and paid is derived as
-- full − saved, so every line reconciles to the cent (assert_marts_reconcile_with_core).
select
    drink_id,
    visit_id,
    date_day,
    bar_id,
    beverage_id,
    is_happy_hour,
    quantity,
    unit_price,
    cast(alcohol_units as numeric(6, 2)) as alcohol_units,
    cast(full_price_amount as numeric(10, 2)) as full_price_amount,
    cast(
        cast(full_price_amount as numeric(10, 2)) - cast(amount_saved as numeric(10, 2)) as numeric(10, 2)
    ) as amount_paid,
    cast(amount_saved as numeric(10, 2)) as amount_saved
from priced
