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
| 3 | P1 | While fixing #1, the agent tried to patch the file with a shell heredoc containing the literal test string `source .env`. | The live `guard_bash.sh` hook blocked the command. That was a false positive, but it showed the hook is active. The edit was redone with the Edit tool. | Hook fired in-session. |
