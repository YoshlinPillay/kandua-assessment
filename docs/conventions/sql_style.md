# SQL style

`sqlfluff` enforces this style (`.sqlfluff`, dialect `postgres`, templater `dbt`). The PostToolUse hook lints every
`.sql` file the agent writes, and pre-commit and CI lint again.

- Lowercase keywords and identifiers. 4-space indent. Trailing commas.
- CTE pipeline shape: `with source as (...), renamed as (...), final as (...) select * from final`.
- Reference other models only with `{{ ref() }}` / `{{ source() }}`. Never hard-code schema names.
- Explicit column lists in `core`/`marts` (no `select *` except the final CTE).
- Explicit join types (`inner join`, `left join`). Join conditions are qualified with CTE aliases.
- Every division is guarded (`nullif(x, 0)`). Every aggregation says in a comment what grain it produces.
- Analyses (`transform/analyses/qN_*.sql`) start with a header comment:
  ```sql
  -- Q<N>: <question text>
  -- Interpretation: <decision, link to docs/decisions.md#qN>
  -- Expected result shape: <columns>
  ```
