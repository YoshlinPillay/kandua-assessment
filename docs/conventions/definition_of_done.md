# Definition of done

A task or phase is done only when **all** of the applicable items hold. When reporting done, state which checks
you ran and paste their summary lines. If something could not be verified, say so explicitly.

## Any change
- [ ] `make lint` passes (ruff, sqlfluff, terraform fmt).
- [ ] No secrets added (`gitleaks` clean).
- [ ] Docs that describe the changed behaviour are updated in the same change.

## Data model / dbt change
- [ ] `docs/erm/*.dbml` matches the models (`pytest tests/test_erm_drift.py`).
- [ ] `make dbt ARGS="build"` passes with zero test failures.
- [ ] New models have a description, column descriptions and tests per `data_quality.md`.

## Answer / metric change
- [ ] SQL in `transform/analyses/`, pandas cross-check in `tests/answers/`, and both agree (`make test`).
- [ ] Interpretation recorded in `docs/decisions.md` and **approved by the user**.
- [ ] Metric defined only in dbt YAML. Cube regenerated (`make cube`). Lightdash and Cube parity test passes.

## Infra change
- [ ] `terraform validate` + `terraform plan` output shown to the user. The user runs `apply`.
- [ ] README deploy section updated.

## Phase checkpoint
- [ ] Summary to the user: built / verified (with evidence) / open decisions.
- [ ] `AI_WORKFLOW.md` updated (work split, guardrails added, corrections).
- [ ] `docs/assessment/requirements.md` checklist updated.
