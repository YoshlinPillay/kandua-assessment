"""Two semantic tools (Lightdash for dashboards, Cube for the chat app) read one metric source (dbt YAML).
They must return the verified Q1–Q7 answers, which equal the independent pandas reference
(tests/answers/reference.py). Skips when the service isn't running or configured."""

import os
import time
from decimal import Decimal

import jwt
import pytest
import requests

from tests.answers import reference as ref

CUBE_URL = os.environ.get("CUBE_URL", "http://localhost:4000/cubejs-api/v1")

# question -> (Cube query, how to read the answer from the result rows)
CUBE_QUESTIONS = {
    "q1": (
        {"measures": ["fct_drink.total_servings"], "dimensions": ["dim_beverage.beverage_type"]},
        lambda rows: {r["dim_beverage.beverage_type"]: int(r["fct_drink.total_servings"]) for r in rows},
        ref.q1_type_servings,
    ),
    "q2": (
        {"measures": ["fct_visit.visits"], "dimensions": ["dim_bar.bar_name"]},
        lambda rows: {r["dim_bar.bar_name"]: int(r["fct_visit.visits"]) for r in rows},
        ref.q2_visits_per_bar,
    ),
    "q3": (
        {
            "measures": ["fct_drink.total_servings"],
            "dimensions": ["dim_beverage.beverage_name"],
            "filters": [{"member": "dim_beverage.beverage_type", "operator": "equals", "values": ["beer"]}],
        },
        lambda rows: {r["dim_beverage.beverage_name"]: int(r["fct_drink.total_servings"]) for r in rows},
        ref.q3_beer_servings,
    ),
    "q4": (
        {"measures": ["fct_visit.visits_without_drink"]},
        lambda rows: int(rows[0]["fct_visit.visits_without_drink"]),
        ref.q4_visits_without_drink,
    ),
    "q5": (
        {"measures": ["fct_daily_consumption.drunk_days_last_30_days"]},
        lambda rows: int(rows[0]["fct_daily_consumption.drunk_days_last_30_days"]),
        lambda: len(ref.q5_drunk_days_last_30()),
    ),
    "q6": (
        {"measures": ["fct_weekly_consumption.avg_weekly_alcohol_units"]},
        lambda rows: round(Decimal(rows[0]["fct_weekly_consumption.avg_weekly_alcohol_units"]), 2),
        lambda: Decimal(str(round(ref.q6_weekly_units().mean(), 2))),
    ),
    "q7": (
        {"measures": ["fct_drink.happy_hour_savings"]},
        lambda rows: Decimal(rows[0]["fct_drink.happy_hour_savings"]),
        ref.q7_happy_hour_savings,
    ),
}


def cube_load(query: dict) -> list[dict]:
    secret = os.environ.get("CUBEJS_API_SECRET")
    if not secret:
        pytest.skip("CUBEJS_API_SECRET not set (run via `make test` with .env)")
    token = jwt.encode({"exp": int(time.time()) + 300}, secret, algorithm="HS256")
    try:
        response = requests.post(
            f"{CUBE_URL}/load", json={"query": query}, headers={"Authorization": token}, timeout=30
        )
    except requests.ConnectionError:
        pytest.skip("Cube is not running")
    response.raise_for_status()
    return response.json()["data"]


@pytest.mark.parametrize("question", sorted(CUBE_QUESTIONS))
def test_cube_returns_verified_answer(question):
    query, read, expected = CUBE_QUESTIONS[question]
    assert read(cube_load(query)) == expected()


# --- Lightdash: run the saved dashboard charts (lightdash/charts/*.yml) and compare with the reference
LIGHTDASH_URL = os.environ.get("LIGHTDASH_TEST_URL", "http://localhost:8100")


def _raw(row: dict, field: str):
    return row[field]["value"]["raw"]


# chart name prefix -> (read answer from rows, expected)
LIGHTDASH_CHARTS = {
    "Q1 ·": (
        lambda rows: {
            _raw(r, "dim_beverage_beverage_type"): int(_raw(r, "fct_drink_total_servings")) for r in rows
        },
        ref.q1_type_servings,
    ),
    "Q2 ·": (
        lambda rows: {_raw(r, "dim_bar_bar_name"): int(_raw(r, "fct_visit_visits")) for r in rows},
        ref.q2_visits_per_bar,
    ),
    "Q3 ·": (
        lambda rows: {
            _raw(r, "dim_beverage_beverage_name"): int(_raw(r, "fct_drink_total_servings")) for r in rows
        },
        ref.q3_beer_servings,
    ),
    "Q4 ·": (
        lambda rows: int(_raw(rows[0], "fct_visit_visits_without_drink")),
        ref.q4_visits_without_drink,
    ),
    "Q5 ·": (
        lambda rows: int(_raw(rows[0], "fct_daily_consumption_drunk_days_last_30_days")),
        lambda: len(ref.q5_drunk_days_last_30()),
    ),
    "Q6 · Average": (
        lambda rows: round(Decimal(str(_raw(rows[0], "fct_weekly_consumption_avg_weekly_alcohol_units"))), 2),
        lambda: Decimal(str(round(ref.q6_weekly_units().mean(), 2))),
    ),
    "Q6 · Weeks": (
        lambda rows: int(_raw(rows[0], "fct_weekly_consumption_weeks_over_nhs_limit")),
        lambda: int((ref.q6_weekly_units() > ref.NHS_WEEKLY_UNITS).sum()),
    ),
    "Q7 ·": (
        lambda rows: Decimal(str(_raw(rows[0], "fct_drink_happy_hour_savings"))),
        ref.q7_happy_hour_savings,
    ),
}


@pytest.fixture(scope="module")
def lightdash_charts():
    key = os.environ.get("LIGHTDASH_API_KEY")
    if not key or key == "changeme":
        pytest.skip("LIGHTDASH_API_KEY not set")
    headers = {"Authorization": f"ApiKey {key}"}
    try:
        projects = requests.get(f"{LIGHTDASH_URL}/api/v1/org/projects", headers=headers, timeout=30).json()
    except requests.ConnectionError:
        pytest.skip("Lightdash is not running")
    project = next(p["projectUuid"] for p in projects["results"] if p["name"] == "Juan the Drinker")
    charts = requests.get(f"{LIGHTDASH_URL}/api/v1/projects/{project}/charts", headers=headers, timeout=30)
    return headers, charts.json()["results"]


@pytest.mark.parametrize("prefix", sorted(LIGHTDASH_CHARTS))
def test_lightdash_dashboard_chart_returns_verified_answer(lightdash_charts, prefix):
    headers, charts = lightdash_charts
    chart = next(c for c in charts if c["name"].startswith(prefix))
    response = requests.post(
        f"{LIGHTDASH_URL}/api/v1/saved/{chart['uuid']}/results", headers=headers, json={}, timeout=60
    )
    response.raise_for_status()
    read, expected = LIGHTDASH_CHARTS[prefix]
    assert read(response.json()["results"]["rows"]) == expected()
