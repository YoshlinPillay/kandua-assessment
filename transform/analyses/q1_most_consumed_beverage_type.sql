-- Q1: What is the beverage type that Juan drinks the most?
-- Interpretation: most servings (sum of drink quantity). Drink lines and alcohol units are shown too, so
-- the answer can be checked under every reasonable reading. Tiger's Milk Lager = beer (D-008).
-- Expected result shape: one row per beverage type, ranked by servings.
with drinks as (
    select
        beverage_type.name as beverage_type,
        drink.quantity,
        drink.quantity * beverage.alcohol_units as alcohol_units
    from {{ ref('drink') }} as drink
    inner join {{ ref('stock') }} as stock on drink.stock_id = stock.stock_id
    inner join {{ ref('beverage') }} as beverage on stock.beverage_id = beverage.beverage_id
    inner join {{ ref('beverage_type') }} as beverage_type
        on beverage.beverage_type_id = beverage_type.beverage_type_id
)

-- grain: one row per beverage type
select
    beverage_type,
    sum(quantity) as servings,
    count(*) as drink_lines,
    sum(alcohol_units) as alcohol_units,
    rank() over (order by sum(quantity) desc) as servings_rank
from drinks
group by beverage_type
order by servings_rank
