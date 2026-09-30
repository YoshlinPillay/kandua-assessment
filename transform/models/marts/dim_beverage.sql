-- Grain: one row per beverage. The type name is folded in from beverage_type so BI never needs the extra
-- join. That's redundancy across tables (the string repeats per beverage), not a normal-form violation within
-- this table: dim_beverage has no beverage_type_id, so the type depends directly on beverage_id (Q10).
select
    beverage.beverage_id,
    beverage.name as beverage_name,
    beverage_type.name as beverage_type,
    beverage.alcohol_units as alcohol_units_per_serving,
    beverage.barcode,
    beverage.is_assumed
from {{ ref('beverage') }} as beverage
inner join {{ ref('beverage_type') }} as beverage_type
    on beverage.beverage_type_id = beverage_type.beverage_type_id
