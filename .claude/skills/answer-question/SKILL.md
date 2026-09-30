---
name: answer-question
description: Produce a verified answer to one of the assessment questions Q1–Q7 (SQL analysis + independent pandas cross-check + decision record). Use when asked to answer, compute or re-check any of Juan's drinking questions.
---

# Answer an assessment question

An answer is only valid when two independent computations agree and the human has approved the interpretation.

## Steps
1. **Interpretation first.** Write the ambiguity down explicitly. Examples: "drunk" per visit vs per day;
   "last month" relative to the data vs to today; ties; how duplicates count. If more than one reading is
   reasonable, compute **each** one and present a table (option → number) to the human. Don't pick one.
2. **SQL.** Create `transform/analyses/q<N>_<slug>.sql` with the header required by
   `docs/conventions/sql_style.md`. Query `core` (transactional) models. Use marts only if the question is
   about the analytical model. Compile with `make dbt ARGS="compile -s q<N>_<slug>"` and run it.
3. **Independent cross-check.** Add `tests/answers/test_q<N>.py`. It computes the same answer **from the raw
   JSON with pandas**, without importing any dbt output, and asserts it equals the SQL result (fetched through
   the `answers` pytest fixture).
4. **Record.**
   - Add the decision to `docs/decisions.md` → "Interpretation decisions" (options, numbers, chosen by human).
   - Add the answer, the SQL and a one-line explanation to `docs/ANSWERS.md`.
5. **Metric.** If the answer is a dashboard tile, make sure the metric exists in dbt YAML `meta` (use the
   `add-metric` skill) so Lightdash and Cube show the same number.

## Done when
`make test` passes, including `tests/answers/test_q<N>.py`, and the human has approved the interpretation.
