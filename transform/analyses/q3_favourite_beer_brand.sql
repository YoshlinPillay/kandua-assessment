-- Q3: What is Juan's favourite beer brand?
-- Interpretation: the beer with the most servings. Black Label is a beer (Carling, C6).
-- Tiger's Milk Lager is an assumed beer (D-008).
-- Expected result shape: one row per beer, ranked by servings (drink lines and units shown too, D-018).
-- grain: one row per beer
select
    beverage.name as beer,
    sum(drink.quantity) as servings,
    count(*) as drink_lines,
    sum(drink.quantity * beverage.alcohol_units) as alcohol_units,
    rank() over (order by sum(drink.quantity) desc) as servings_rank
from {{ ref('drink') }} as drink
inner join {{ ref('stock') }} as stock on drink.stock_id = stock.stock_id
inner join {{ ref('beverage') }} as beverage on stock.beverage_id = beverage.beverage_id
inner join {{ ref('beverage_type') }} as beverage_type
    on beverage.beverage_type_id = beverage_type.beverage_type_id
where beverage_type.name = 'beer'
group by beverage.name
order by servings_rank, beer
