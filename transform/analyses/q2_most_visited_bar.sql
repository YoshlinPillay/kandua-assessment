-- Q2: What is the bar Juan visits the most?
-- Interpretation: count every visit in core.visit, including visits without a drink (D-006, D-013).
-- No join to drink: counting only visits with a drink would change the winner. The full ranking is
-- returned because the margin is one visit.
-- Expected result shape: one row per bar with visits and rank.
-- grain: one row per bar
select
    bar.name as bar_name,
    count(*) as visits,
    rank() over (order by count(*) desc) as visits_rank
from {{ ref('visit') }} as visit
inner join {{ ref('bar') }} as bar on visit.bar_id = bar.bar_id
group by bar.name
order by visits_rank, bar_name
