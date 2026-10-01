"""Conversational analytics agent: an LLM on Amazon Bedrock (Converse API) with two read-only Cube tools.

Model-agnostic on purpose (D-020): the same loop runs OpenAI gpt-oss and Claude, so the golden-question
bake-off (chat/bakeoff.py) compares models, not harnesses. Guardrails:
- Numbers may only come from tool results (system prompt) and every answer carries the Cube queries behind it.
- Members are validated against the Cube catalogue before a query runs (CubeClient.validate).
- Assistant turns are appended unchanged, including any reasoning blocks (thinking blocks are bound to the
  conversation on current Claude models), and all tool results of a turn go back in ONE user message.
- A hard cap on tool rounds stops runaway loops.
"""

import json
from dataclasses import dataclass, field
from typing import Any, Protocol

from chat.cube_client import CubeClient, CubeQueryError

MAX_TOOL_ROUNDS = 6

SYSTEM_PROMPT = """You answer questions about Juan's drinking habits (bars, beverages, visits, alcohol units,
spending) from a governed semantic layer. The data covers 2018-01-03 to 2019-09-22.

How to work:
- Call list_metrics first to see the available measures and dimensions, then run_query to get numbers.
- Use the metric whose description matches the question. Definitions such as "drunk", "last month",
  the NHS weekly limit, happy-hour savings and rounding are already encoded in the metric descriptions:
  use them as they are and don't redefine them.
- Every number in your answer must come from a run_query result in this conversation. Never estimate, compute
  from memory, or invent numbers. If the metrics can't answer the question, say so plainly.
- Report numbers at the precision the query returns (two decimals for averages and money); don't round
  further or write "about".
- Prices are assumed to be ZAR (shown as R). Tiger's Milk Lager is an assumed 1.2-unit beer.
- Answer in one to three sentences, leading with the answer. Mention a close second where it matters
  (e.g. a one-visit margin)."""

TOOLS = [
    {
        "toolSpec": {
            "name": "list_metrics",
            "description": "List the governed cubes with their measures and dimensions (exact member names "
            "and descriptions). Call this before writing any query.",
            "inputSchema": {"json": {"type": "object", "properties": {}, "additionalProperties": False}},
        }
    },
    {
        "toolSpec": {
            "name": "run_query",
            "description": "Run a Cube metric query and return the rows. Members must be exact names from "
            "list_metrics, e.g. 'fct_drink.total_servings' or 'dim_bar.bar_name'.",
            "inputSchema": {
                "json": {
                    "type": "object",
                    "properties": {
                        "measures": {"type": "array", "items": {"type": "string"}},
                        "dimensions": {"type": "array", "items": {"type": "string"}},
                        "filters": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "properties": {
                                    "member": {"type": "string"},
                                    "operator": {
                                        "type": "string",
                                        "enum": [
                                            "equals",
                                            "notEquals",
                                            "gt",
                                            "gte",
                                            "lt",
                                            "lte",
                                            "set",
                                            "notSet",
                                        ],
                                    },
                                    "values": {"type": "array", "items": {"type": "string"}},
                                },
                                "required": ["member", "operator"],
                            },
                        },
                        "order": {
                            "type": "object",
                            "description": "Map of member to 'asc' or 'desc'.",
                            "additionalProperties": {"type": "string", "enum": ["asc", "desc"]},
                        },
                        "limit": {"type": "integer", "minimum": 1, "maximum": 1000},
                    },
                    "additionalProperties": False,
                }
            },
        }
    },
]


class ConverseModel(Protocol):
    """The subset of bedrock-runtime used here; tests pass a scripted fake."""

    def converse(self, **kwargs: Any) -> dict: ...


@dataclass
class TurnResult:
    answer: str
    queries: list[dict] = field(default_factory=list)  # every Cube query run this turn, with its rows
    tool_rounds: int = 0
    stop_reason: str = ""
    usage: dict = field(default_factory=dict)


def _run_tool(name: str, tool_input: dict, cube: CubeClient, trace: list[dict]) -> tuple[dict, str]:
    """Execute one tool call -> (json content, status). Invalid queries become tool errors, not crashes."""
    if name == "list_metrics":
        return {"cubes": cube.catalogue()}, "success"
    if name == "run_query":
        try:
            rows = cube.load(tool_input)
        except CubeQueryError as exc:
            trace.append({"query": tool_input, "error": str(exc)})
            return {"error": str(exc)}, "error"
        trace.append({"query": tool_input, "rows": rows})
        return {"rows": rows}, "success"
    return {"error": f"Unknown tool {name}"}, "error"


def answer(
    question: str, history: list[dict], model: ConverseModel, model_id: str, cube: CubeClient
) -> TurnResult:
    """Run one user turn to completion. `history` is appended to, so follow-up questions keep context."""
    history.append({"role": "user", "content": [{"text": question}]})
    trace: list[dict] = []
    usage: dict = {}

    for rounds in range(MAX_TOOL_ROUNDS + 1):
        response = model.converse(
            modelId=model_id,
            system=[{"text": SYSTEM_PROMPT}],
            messages=history,
            toolConfig={"tools": TOOLS, "toolChoice": {"auto": {}}},
            inferenceConfig={"maxTokens": 4096},
        )
        for key, value in response.get("usage", {}).items():
            usage[key] = usage.get(key, 0) + value
        message = response["output"]["message"]
        history.append(message)  # unchanged: keeps reasoning blocks valid for the next request
        stop_reason = response.get("stopReason", "")

        tool_uses = [block["toolUse"] for block in message["content"] if "toolUse" in block]
        if stop_reason != "tool_use" or not tool_uses:
            text = "\n".join(block["text"] for block in message["content"] if "text" in block).strip()
            return TurnResult(text, trace, rounds, stop_reason, usage)

        if rounds == MAX_TOOL_ROUNDS:
            break

        results = []
        for tool_use in tool_uses:
            content, status = _run_tool(tool_use["name"], tool_use.get("input") or {}, cube, trace)
            results.append(
                {
                    "toolResult": {
                        "toolUseId": tool_use["toolUseId"],
                        "content": [{"json": json.loads(json.dumps(content, default=str))}],
                        "status": status,
                    }
                }
            )
        history.append({"role": "user", "content": results})  # all results of the turn in ONE message

    # Cap reached with tool calls still pending: answer them with an error so the history stays valid.
    history.append(
        {
            "role": "user",
            "content": [
                {
                    "toolResult": {
                        "toolUseId": tool_use["toolUseId"],
                        "content": [{"json": {"error": "Tool budget exhausted for this question."}}],
                        "status": "error",
                    }
                }
                for tool_use in tool_uses
            ],
        }
    )
    return TurnResult(
        "I couldn't answer that within the query budget. Please rephrase or narrow the question.",
        trace,
        MAX_TOOL_ROUNDS,
        "tool_budget_exhausted",
        usage,
    )
