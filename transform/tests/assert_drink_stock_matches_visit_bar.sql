-- D-011: the stock line a drink points to must belong to the bar of the drink's visit.
-- Not expressible as a plain FK without breaking 3NF, so it is enforced here. Returns violating rows.
select
    drink.drink_id,
    visit.bar_id as visit_bar_id,
    stock.bar_id as stock_bar_id
from {{ ref('drink') }} as drink
inner join {{ ref('visit') }} as visit on drink.visit_id = visit.visit_id
inner join {{ ref('stock') }} as stock on drink.stock_id = stock.stock_id
where visit.bar_id != stock.bar_id
