-- Q4: How many times did Juan visit a bar and not have a drink?
-- Interpretation: visits (one per source event, D-006) with no drink line. Duplicate-looking events are kept
-- (D-007). The (bar, date) reading gives 74 and is reported as a sensitivity in docs/ANSWERS.md.
-- Expected result shape: one row: visits_without_drink, total_visits.
-- grain: one row (whole dataset)
select
    count(*) filter (
        where not exists (
            select 1 from {{ ref('drink') }} as drink
            where drink.visit_id = visit.visit_id
        )
    ) as visits_without_drink,
    count(*) as total_visits
from {{ ref('visit') }} as visit
