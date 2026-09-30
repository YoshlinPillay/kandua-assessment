-- Grain: one row per drink line (a beverage ordered on a visit, at happy-hour price or not).
-- All money and unit arithmetic happens here once, so Lightdash, Cube and the chat app only ever sum.
with drinks as (
    select * from {{ ref('drink') }}
),

visits as (
    select * from {{ ref('visit') }}
),

stock as (
    select * from {{ ref('stock') }}
),

beverages as (
    select * from {{ ref('beverage') }}
)

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
    case
        when drinks.is_happy_hour then stock.price * drinks.quantity * 0.5
        else stock.price * drinks.quantity
    end as amount_paid,
    case
        when drinks.is_happy_hour then stock.price * drinks.quantity * 0.5
        else 0
    end as amount_saved
from drinks
inner join visits on drinks.visit_id = visits.visit_id
inner join stock on drinks.stock_id = stock.stock_id
inner join beverages on stock.beverage_id = beverages.beverage_id
