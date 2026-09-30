-- Q7: How much money has Juan saved by drinking during Happy Hours (always a 50% discount)?
-- Interpretation: stock.price is the full price; a happy-hour drink costs 50% of it. Each line's saving is
-- rounded to the cent like a bill (D-022), and paid = full − saved. Currency assumed ZAR (D-019).
-- Expected result shape: one row: happy-hour lines, servings, full-price value, amount paid, amount saved.

-- grain: one row per happy-hour drink line
with happy_hour_lines as (
    select
        drink.quantity,
        stock.price * drink.quantity as full_price,
        round(stock.price * drink.quantity * 0.5, 2) as saved
    from {{ ref('drink') }} as drink
    inner join {{ ref('stock') }} as stock on drink.stock_id = stock.stock_id
    where drink.is_happy_hour
)

-- grain: one row (all happy-hour drink lines)
select
    count(*) as happy_hour_drink_lines,
    sum(quantity) as happy_hour_servings,
    sum(full_price) as full_price_value,
    sum(full_price) - sum(saved) as amount_paid,
    sum(saved) as amount_saved
from happy_hour_lines
