-- D-009: the source reuses barcodes (Jose Cuervo / Don Julio = 24199034). Kept, but kept visible.
{{ config(severity='warn') }}
select
    barcode,
    count(*) as beverages,
    string_agg(name, ', ' order by name) as beverage_names
from {{ ref('beverage') }}
where barcode is not null
group by barcode
having count(*) > 1
