# AI workflow

How this solution was built with an AI agent. It covers which agent was used, how the work was split, which guardrails
exist and why, and where the agent had to be corrected. The document is kept up to date phase by phase.

## Agent and models
| Role | Tool / model | Used for |
|---|---|---|
| Primary coding agent | Claude Code (CLI) · Claude Opus 5.5 | Planning, implementation, verification |
| Reviewer subagent | `.claude/agents/data-reviewer.md` (Opus, read-only tools) | Independent review of models, SQL and DBML before each checkpoint |
| Runtime LLM (chat app) | Claude via Anthropic API (tool use over Cube) | Conversational analytics. Not used to produce the assessment answers. |

## How the work was split
**Human (Yoshlin) decides.** This covers the stack, hosting, the interpretation of every question, how
conflicting or duplicate data is handled, and every `terraform apply`. **Agent proposes and implements.** It
explains the options with trade-offs, writes code and docs, runs checks, and stops at each phase checkpoint.

| Phase | Human | Agent |
|---|---|---|
| Planning | Chose the stack. Rejected Mage.ai and Render. Asked for Cube + conversational analytics and AWS. | Read the brief, surveyed the server, explained dlt, Dagster and Lightdash, and presented the options and constraints (Render free PG expiry, Lightdash AI is enterprise-only). |
| P1 Guardrails | Reviewed the rules | Wrote `CLAUDE.md`, conventions, hooks, skills, the subagent and the hook tests |
| P4 Load | Created `.env` with their own passwords (the agent can't read it). Fixed the agent's over-broad deny rule. | Compose, dlt, dbt (contracts, tests), Dagster, CI pipeline job, live drift and role tests |
| P2 Profile | Chose the visit grain (after asking for concrete examples and whether any time signal exists), duplicate handling, the Tiger's Milk Lager assumption and the key strategy | Profiled all 3 files, showed the sensitivity of each open question in numbers (e.g. Q4 = 104 vs 74), checked for hidden time signals (uuid version, file order) |

## Guardrails and why
| Guardrail | Type | Why |
|---|---|---|
| `CLAUDE.md` hard rules | Instructions | Encode what the brief is testing: profile before modeling, human owns interpretations, traceability. |
| `docs/conventions/*.md` | Standards | Give the agent concrete standards for modeling, SQL, DQ, security and definition of done, instead of relying on its defaults. |
| `guard_files.sh` (PreToolUse) | Deterministic block | The agent physically can't edit `.env`, tfstate, raw data or generated Cube models. |
| `guard_bash.sh` (PreToolUse) | Deterministic block | Destructive or irreversible operations (`terraform apply`, `DROP`, `compose down -v`, force-push, reading `.env`) are handed to the human. This host also runs unrelated services, which makes `docker volume prune` dangerous. |
| `lint_changed.sh` (PostToolUse) | Deterministic feedback | Every SQL, Python or YAML file the agent writes is linted immediately (sqlfluff, ruff, dbt parse). Failures go straight back to the agent. |
| `tests/hooks/test_hooks.sh` | Test of the guardrails | The guardrails themselves are tested (block and allow cases), and pre-commit and CI run the tests. |
| Skills: `profile-raw-data`, `answer-question`, `add-metric` | Repeatable procedures | Each skill forces the same evidence-first workflow every time. |
| Dual computation of answers | Verification | Every Q1–Q7 number is computed once in SQL and once with pandas from the raw JSON, and pytest asserts they match. |
| Lightdash ↔ Cube parity test | Verification | Two semantic tools must never disagree. |
| `docs/decisions.md` | Audit trail | Records who decided what, and why. |
| `.claude/settings.json` deny rules | Permissions | The agent can't read secrets files. |

## Corrections log
| # | Phase | What the agent did or assumed | What was actually right | How it was caught |
|---|---|---|---|---|
| 1 | P1 | The first version of the "don't read `.env`" regex in `guard_bash.sh` let `cat .env` through (the whitespace after the command was consumed twice by the pattern). | The pattern needed a word-boundary-style prefix and an optional middle segment. | `tests/hooks/test_hooks.sh` failed on the `cat .env` case. |
| 2 | P1 | The PostToolUse lint hook ran `sqlfluff`/`dbt parse` inside a subshell, so their `exit 2` would never reach Claude Code. | Run in the main shell so the exit code propagates. | Agent self-review of the hook before running it. |
| 4 | P2 | On first sight the agent flagged "Black Label" (typed `beer`, 1.2 units) as a likely mislabelled Johnnie Walker whiskey. | In the Cape Town context it is Carling Black Label, a beer. The catalog's units and price are consistent with that, so it was kept as beer rather than "fixed". | Agent re-checked against the domain context and the price and units before writing it into the profile. The profiling skill forbids fixing data during profiling. |
| 5 | P3 | `pyproject.toml` relied on setuptools auto-discovery. Once `data/` existed, `pip install -e .` failed with "multiple top-level packages", and CI would have failed the same way. | Declare the packages explicitly (`[tool.setuptools.packages.find]`). | Failed install when adding `pydbml`. |
| 6 | P3 | The agent's profile and ERM passed its own checks. | The independent `data-reviewer` subagent found 9 issues. Two were major: **Q2 is decided by 1 visit** and changes winner if only visits with drinks are counted, and the NHS weekly counts silently used ISO weeks. Minor ones: the "shared address" warn test would never fire because the strings differ ("Rd" vs "Road"); `UNIQUE(visit_id, stock_id)` contradicted "a visit can have many drinks"; and more. All were fixed and D-013 was added. | Human asked for the reviewer run at the P3 checkpoint. |
| 7 | P4 | The agent's own deny rule `Read(./.env.*)` also blocked writing `.env.example` (placeholders only). | The rule should cover real secrets files only. The agent was (correctly) not allowed to edit its own `.claude/settings.json`, so the fix was handed to the human. | Write was refused by the permission system. |
| 8 | P4 | `profiles.yml` required DB credentials even for `dbt parse`, so the PostToolUse lint hook failed on the first YAML model. | Non-secret defaults (`juan_admin`, empty password) let parse and compile work without a `.env`. Real runs still need `.env`. | PostToolUse hook `lint_changed.sh`. |
| 9 | P4 | The agent wrote dbt SQL files through shell heredocs. | The PostToolUse lint hook only fires on Edit/Write, so those files were never linted. Pre-commit caught it at commit time (defense in depth). Rule adopted: write model files with the Write/Edit tools so the hook runs. | `pre-commit` blocked the commit. |
| 10 | P4 | sqlfluff used the dbt templater, which needs a live database just to lint. The lint hook also passed `--nofail-on-unparsable`, a flag removed in sqlfluff 4, so it would have failed on every SQL write. | Switched to the Jinja templater with dbt builtins plus stubs for `dbt_utils`, so linting runs offline. Removed the flag and added a regression case to `tests/hooks/test_hooks.sh` (a bad SQL file must be blocked). | `pre-commit` failure, then the hook's own error message. |
| 11 | P4 | To join the dlt and dbt lineage, the agent mapped both dbt sources `bars` and `bars__stock` to the single dlt asset key `juan_raw/bars`. | Dagster requires a unique key per dbt source. `bars__stock` is now its own asset, declared downstream of the dlt `bars` load, which is also the more honest lineage. | Dagster raised `DagsterInvalidDefinitionError` at load time. |
| 3 | P1 | While fixing #1, the agent tried to patch the file with a shell heredoc containing the literal test string `source .env`. | The live `guard_bash.sh` hook blocked the command. That was a false positive, but it showed the hook is active. The edit was redone with the Edit tool. | Hook fired in-session. |
