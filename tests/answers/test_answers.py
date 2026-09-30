"""Q1–Q7: the SQL analyses (transform/analyses, run against dbt `core`) must equal the independent pandas
reference (tests/answers/reference.py, straight from the raw JSON). Run via `make test`, which compiles the
analyses first. A number goes into the docs or dashboard only when both computations agree."""

from decimal import Decimal
from pathlib import Path

import pytest

from tests.answers import reference as ref
from tests.warehouse import connect_or_skip

COMPILED = Path(__file__).resolve().parents[2] / "transform/target/compiled/juan/analyses"


def run_analysis(name: str) -> list[dict]:
    path = COMPILED / f"{name}.sql"
    if not path.exists():
        pytest.skip(f"{path.name} not compiled: run `make test` (it compiles analyses first)")
    with connect_or_skip() as conn:
        cur = conn.execute(path.read_text())
        cols = [c.name for c in cur.description]
        return [dict(zip(cols, row, strict=True)) for row in cur.fetchall()]


def test_q1_most_consumed_beverage_type():
    rows = run_analysis("q1_most_consumed_beverage_type")
    assert {r["beverage_type"]: int(r["servings"]) for r in rows} == ref.q1_type_servings()
    assert rows[0]["beverage_type"] == "beer" and rows[0]["servings_rank"] == 1


def test_q2_most_visited_bar():
    rows = run_analysis("q2_most_visited_bar")
    assert {r["bar_name"]: r["visits"] for r in rows} == ref.q2_visits_per_bar()
    winners = [r["bar_name"] for r in rows if r["visits_rank"] == 1]
    assert winners == ["Yours Truly"]  # a tie would return two rows here: fail loudly rather than pick one


def test_q3_favourite_beer_brand():
    rows = run_analysis("q3_favourite_beer_brand")
    assert {r["beer"]: int(r["servings"]) for r in rows} == ref.q3_beer_servings()
    assert [r["beer"] for r in rows if r["servings_rank"] == 1] == ["Castle Lite"]


def test_q4_visits_without_drink():
    (row,) = run_analysis("q4_visits_without_drink")
    assert row["visits_without_drink"] == ref.q4_visits_without_drink()
    assert row["total_visits"] == 1000


def test_q5_times_drunk_last_month():
    rows = run_analysis("q5_times_drunk_last_month")
    drunk_days = [r["visited_on"].isoformat() for r in rows if r["is_drunk"]]
    assert drunk_days == ref.q5_drunk_days_last_30()
    assert all(r["times_drunk"] == len(drunk_days) for r in rows)


def test_q6_nhs_weekly_units():
    (row,) = run_analysis("q6_nhs_weekly_units")
    weekly = ref.q6_weekly_units()
    assert row["weeks"] == len(weekly)
    assert row["weeks_over_limit"] == int((weekly > ref.NHS_WEEKLY_UNITS).sum())
    assert row["avg_units_per_week"] == Decimal(str(round(weekly.mean(), 2)))
    assert row["exceeds_nhs_guidance"] == ("Yes" if weekly.mean() > ref.NHS_WEEKLY_UNITS else "No")


def test_q7_happy_hour_savings():
    (row,) = run_analysis("q7_happy_hour_savings")
    assert row["amount_saved"] == Decimal(str(ref.q7_happy_hour_savings()))
    assert row["amount_paid"] + row["amount_saved"] == row["full_price_value"]
