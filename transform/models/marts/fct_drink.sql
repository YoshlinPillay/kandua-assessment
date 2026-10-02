-- Grain: one row per drink line (a beverage ordered on a visit, at happy-hour price or not).
-- The arithmetic lives in int_drink_lines, so Lightdash, Cube and the chat app only ever sum.
select
    drink_id,
    visit_id,
    date_day,
    bar_id,
    beverage_id,
    is_happy_hour,
    quantity,
    unit_price,
    alcohol_units,
    full_price_amount,
    amount_paid,
    amount_saved
from {{ ref('int_drink_lines') }}
