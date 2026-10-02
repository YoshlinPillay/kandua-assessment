# Evaluation: Altimate Code (data-engineering agent harness)

**Question (from the human):** could [Altimate Code](https://github.com/AltimateAI/altimate-code) (MIT, v0.12.4)
strengthen this project's agent setup? It offers deterministic SQL checks, column-level lineage, dbt unit-test
generation and governance features, and can mount into Claude Code.

**Decision: not adopted (D-035).** The deterministic checker found nothing actionable in this dbt project, and
the LLM features don't work on Amazon Bedrock in 0.12.4. Everything below can be reproduced with
`docker/altimate/Dockerfile`.

## How it was evaluated (guardrails)

- **Pinned and isolated:** npm `altimate-code@0.12.4` in its own container (`docker/altimate/Dockerfile`).
  Not installed on the host, and the Claude Code setup was not modified (`/configure-claude` was not run).
- **On a sanitised copy:** `git archive HEAD`, so no `.env`, raw data or virtualenv. It could not modify
  the repository.
- **Read-only:** the `analyst` agent, not the default `builder` (which has write access).
- **Our models, our account:** Bedrock with short-lived `aws login` credentials, not Altimate's hosted
  "Altimate Base" model, which may log requests.

## 1. Deterministic checks (`altimate-code check`, no LLM)

Run over the 97 compiled SQL files (dbt models, tests and Q1–Q7 analyses), checks `lint,safety`:
**119 findings (12 errors, 104 warnings, 3 info). 0 actionable.**

| Findings | Rule | Assessment |
|---|---|---|
| 94 | `select-without-limit` | False positive. A dbt model must return every row; a LIMIT would silently drop data. |
| 6 | `unbalanced_quote` ("injection breakout") | False positive. Apostrophes inside SQL **comments** ("Tiger's Milk", "isn't"); the checker doesn't strip comments. |
| 2 | `union_injection` | False positive. Deliberate `UNION ALL` (date spine; catalog + supplement), and no user input reaches these queries. |
| 4 | `aggregation-before-join` | False positive, and **the suggested fix would introduce a bug**. We aggregate first on purpose and then left-join to a calendar, so zero days survive. Joining first causes row fan-out. |
| 3 | `window_without_partition` | Intended: `rank()` over all bars/beverages is the question. |
| 8 | `select_star` | dbt-generated test SQL, plus the standard dbt staging import CTE (allowed by our conventions). |
| 2 | `function-on-filter-column` | `TRIM()` on a one-row seed, and `LENGTH()` inside a dbt test. No index matters at this scale. |

The rules target application SQL (unbounded selects, string-built queries), not batch transformation code.
As a CI gate it would block on noise and nudge towards harmful "fixes". **Not added.** sqlfluff, the
dbt tests and the reviewer subagent already cover style and logic.

## 2. LLM features (`altimate-code run`: dbt unit tests, review, lineage)

These were blocked before producing anything:

| Finding | Detail |
|---|---|
| Credential bug | With an AWS profile (our `aws login` session) the Bedrock provider crashes: `parseKnownFiles is not a function`. Workaround: export short-lived credentials as environment variables. |
| **Undisclosed second model** | Besides the chosen model, it silently calls `global.anthropic.claude-haiku-4-5` (a "small model" for titles) through **global** cross-region inference. That is a model and data path we hadn't approved. It can be pinned with `small_model` in `altimate-code.json`. |
| Hosted default | With no provider set it uses "Altimate Base", which may log requests and responses. |
| **No output on Bedrock** | With `openai.gpt-oss-120b-1:0` (our chat model) and `us.amazon.nova-pro-v1:0` (both slots pinned), every step ends `finish=other` with no text and no tool calls. The same two models answer correctly through Bedrock with our own boto3 code, so the fault is in Altimate 0.12.4's Bedrock integration. |

The dbt unit tests it would have generated are a **native dbt (1.8+) feature**. They are recorded as a
follow-up to write directly, without the tool.

## What this shows about the agent setup

The isolation guardrails paid off. The tool's defaults were write-capable, used an undisclosed second
model, and pointed at a hosted LLM. The pinned container, sanitised copy, analyst agent and Bedrock-only
credentials kept all of that away from the repo, the warehouse and unapproved providers. "Adopt a tool"
was decided on measured output, not on its README.
