-- Q7: How much money has Juan saved by drinking during Happy Hours (always a 50% discount)?
-- Interpretation: stock.price is the full price. A happy-hour drink costs 50% of it, so the saving per line
-- = 0.5 × price × quantity. Currency: ZAR (Cape Town bars; not stated in the source).
-- Expected result shape: one row: happy-hour lines, servings, full-price value, amount paid, amount saved.
select
    count(*) as happy_hour_drink_lines,
    sum(drink.quantity) as happy_hour_servings,
    round(sum(stock.price * drink.quantity), 2) as full_price_value,
    round(sum(stock.price * drink.quantity) - sum(stock.price * drink.quantity * 0.5), 2) as amount_paid,
    round(sum(stock.price * drink.quantity * 0.5), 2) as amount_saved
from {{ ref('drink') }} as drink
inner join {{ ref('stock') }} as stock on drink.stock_id = stock.stock_id
where drink.is_happy_hour
