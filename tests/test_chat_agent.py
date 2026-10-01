"""Chat agent tests with a scripted model and a fake Cube: no Bedrock, no network.

They pin the guardrails: tool results go back in one message, invalid members become tool errors (not crashes
and not invented answers), the tool budget is enforced while keeping the history valid, and the bake-off
grader can't be fooled by substrings ("1" inside "14") or ungrounded numbers.
"""

import pytest

from chat.agent import MAX_TOOL_ROUNDS, answer
from chat.bakeoff import _contains_value, _grounded
from chat.cube_client import CubeClient, CubeQueryError

CATALOGUE = {
    "fct_drink": {
        "description": "",
        "measures": {"fct_drink.happy_hour_savings": "Happy-hour savings (Q7, ZAR)"},
        "dimensions": {"fct_drink.is_happy_hour": "boolean"},
    }
}


class FakeCube(CubeClient):
    def __init__(self):
        super().__init__(url="http://fake", secret="test")  # noqa: S106 - fake, never used to sign
        self._catalogue = CATALOGUE
        self.loaded: list[dict] = []

    def load(self, query: dict) -> list[dict]:
        self.validate(query)
        self.loaded.append(query)
        return [{"fct_drink.happy_hour_savings": "21587.09"}]


class ScriptedModel:
    """Returns pre-baked Converse responses in order and records the requests it saw."""

    def __init__(self, *messages: dict):
        self.responses = list(messages)
        self.requests: list[dict] = []

    def converse(self, **kwargs):
        self.requests.append(kwargs)
        message = self.responses.pop(0)
        stop = "tool_use" if any("toolUse" in b for b in message["content"]) else "end_turn"
        return {"output": {"message": message}, "stopReason": stop, "usage": {"inputTokens": 10}}


def tool_call(tool_id: str, name: str, payload: dict) -> dict:
    return {
        "role": "assistant",
        "content": [{"toolUse": {"toolUseId": tool_id, "name": name, "input": payload}}],
    }


def text(msg: str) -> dict:
    return {
        "role": "assistant",
        "content": [{"reasoningContent": {"reasoningText": {"text": "…"}}}, {"text": msg}],
    }


GOOD_QUERY = {"measures": ["fct_drink.happy_hour_savings"]}


def test_tool_loop_answers_from_query_results():
    model = ScriptedModel(
        tool_call("t1", "list_metrics", {}),
        tool_call("t2", "run_query", GOOD_QUERY),
        text("Juan saved R 21,587.09 on happy hours."),
    )
    history: list[dict] = []
    result = answer("How much did Juan save?", history, model, "test-model", FakeCube())

    assert result.answer == "Juan saved R 21,587.09 on happy hours."
    assert result.queries == [{"query": GOOD_QUERY, "rows": [{"fct_drink.happy_hour_savings": "21587.09"}]}]
    assert result.tool_rounds == 2
    # assistant turns are kept unchanged (reasoning block included), roles alternate, tool choice stays auto
    assert history[-1]["content"][0] == {"reasoningContent": {"reasoningText": {"text": "…"}}}
    assert [m["role"] for m in history] == ["user", "assistant", "user", "assistant", "user", "assistant"]
    assert all(r["toolConfig"]["toolChoice"] == {"auto": {}} for r in model.requests)


def test_parallel_tool_calls_return_in_a_single_message():
    both = {
        "role": "assistant",
        "content": [
            {"toolUse": {"toolUseId": "a", "name": "run_query", "input": GOOD_QUERY}},
            {"toolUse": {"toolUseId": "b", "name": "run_query", "input": GOOD_QUERY}},
        ],
    }
    history: list[dict] = []
    answer("q", history, ScriptedModel(both, text("done")), "m", FakeCube())
    tool_results = history[2]["content"]
    assert [r["toolResult"]["toolUseId"] for r in tool_results] == ["a", "b"]


def test_unknown_member_becomes_a_tool_error_not_a_crash():
    bad = {"measures": ["fct_drink.invented_metric"]}
    model = ScriptedModel(tool_call("t1", "run_query", bad), text("I can't answer that from the metrics."))
    cube = FakeCube()
    history: list[dict] = []
    result = answer("q", history, model, "m", cube)

    tool_result = history[2]["content"][0]["toolResult"]
    assert tool_result["status"] == "error"
    assert "Unknown members" in tool_result["content"][0]["json"]["error"]
    assert cube.loaded == []  # the invalid query never reached Cube
    assert "error" in result.queries[0]


def test_tool_budget_is_enforced_and_history_stays_valid():
    endless = [tool_call(f"t{i}", "list_metrics", {}) for i in range(MAX_TOOL_ROUNDS + 1)]
    history: list[dict] = []
    result = answer("q", history, ScriptedModel(*endless), "m", FakeCube())

    assert result.stop_reason == "tool_budget_exhausted"
    assert history[-1]["role"] == "user"  # the pending tool call was answered, so the next turn is valid
    assert history[-1]["content"][0]["toolResult"]["status"] == "error"


def test_validate_rejects_unknown_members_everywhere():
    cube = FakeCube()
    with pytest.raises(CubeQueryError):
        cube.validate({"measures": ["fct_drink.happy_hour_savings"], "order": {"x.y": "desc"}})
    with pytest.raises(CubeQueryError):
        cube.validate({})


@pytest.mark.parametrize(
    ("text_", "expected", "ok"),
    [
        ("Juan saved R 21,587.09.", "21587.09", True),
        ("Juan saved **R 21\u202f587.09**", "21587.09", True),  # space as thousands separator (gpt-oss)
        ("1 time in 2019, 14 units", "1", True),
        ("Juan saved R 21,587.05.", "21587.09", False),
        ("He was drunk 14 times", "1", False),  # whole-number match, not substring
        ("He was drunk 1 time (2019-08-31)", "1", True),
        ("Yours Truly, with 207 visits", "Yours Truly", True),
        ("33.24 units per week", "33.24", True),
        ("about **33.2** units per week", "33.24", False),  # less precise than the governed value
        ("Juan\u2019s favourite is **Castle\u202fLite**", "Castle Lite", True),  # unicode spaces (gpt-oss)
    ],
)
def test_bakeoff_value_matching(text_, expected, ok):
    assert _contains_value(text_, expected) is ok


def test_bakeoff_grounding_requires_the_value_in_query_rows():
    queries = [{"query": GOOD_QUERY, "rows": [{"fct_drink.happy_hour_savings": "21587.09"}]}]
    assert _grounded(queries, "21587.09")
    assert not _grounded(queries, "104")
    assert not _grounded([], "21587.09")
