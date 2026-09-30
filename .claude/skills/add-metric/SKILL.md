---
name: add-metric
description: Add or change a business metric/dimension in the single semantic source (dbt YAML meta) and propagate it to Lightdash and Cube. Use whenever a dashboard tile, chat capability or KPI needs a new or changed measure.
---

# Add a metric (single source of truth)

Metrics live **only** in `transform/models/marts/*.yml` under `meta`. Lightdash reads them natively. Cube models
are generated from them. The chat app discovers them via Cube `/meta`.

## Steps
1. Choose the mart model whose grain matches the metric (e.g. `fct_drink`: one row per drink line).
2. Define it in the model YAML:
   ```yaml
   columns:
     - name: alcohol_units
       description: quantity × beverage alcohol units for this drink line
       meta:
         metrics:
           total_alcohol_units:
             type: sum
             label: Total alcohol units
             description: Sum of alcohol units consumed
   ```
   Use additive columns precomputed in the mart. Don't put arithmetic in the metric definition unless it
   can't be avoided.
3. `make dbt ARGS="build -s <model>"`. Then `make cube`, which regenerates `semantic/cube/model/` from the
   dbt manifest. Never hand-edit those files (a hook blocks it).
4. `make lightdash-deploy` to push the updated semantic layer to Lightdash.
5. If the metric backs a Q1–Q7 answer, add or extend `tests/test_semantic_parity.py` so Lightdash, Cube and the
   SQL analysis are asserted equal.
