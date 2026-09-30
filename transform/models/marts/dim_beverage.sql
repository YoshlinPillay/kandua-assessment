-- Grain: one row per beverage. Deliberately denormalized: the type name is folded in from beverage_type
-- (a transitive dependency, so not 3NF; see docs/ANSWERS.md Q10) so BI never needs the extra join.
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
