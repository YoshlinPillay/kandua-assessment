"""The dashboard reads the star schema (marts), not the analyses. So the marts must reproduce every verified
Q1–Q7 answer, computed here from marts and compared with the independent pandas reference."""

from decimal import Decimal

import pandas as pd

from tests.answers import reference as ref
from tests.warehouse import connect_or_skip


def query(sql: str) -> list[tuple]:
    with connect_or_skip() as conn:
        return conn.execute(sql).fetchall()


def test_q1_q3_from_marts():
    by_type = dict(
        query(
            "select b.beverage_type, sum(f.quantity)::int from marts.fct_drink f "
            "join marts.dim_beverage b using (beverage_id) group by 1"
        )
    )
    assert by_type == ref.q1_type_servings()
    beers = dict(
        query(
            "select b.beverage_name, sum(f.quantity)::int from marts.fct_drink f "
            "join marts.dim_beverage b using (beverage_id) where b.beverage_type = 'beer' group by 1"
        )
    )
    assert beers == ref.q3_beer_servings()


def test_q2_q4_from_marts():
    visits = dict(
        query(
            "select b.bar_name, count(*) from marts.fct_visit v "
            "join marts.dim_bar b using (bar_id) group by 1"
        )
    )
    assert visits == ref.q2_visits_per_bar()
    ((no_drink,),) = query("select count(*) from marts.fct_visit where not has_drink")
    assert no_drink == ref.q4_visits_without_drink()


def test_q5_from_marts():
    rows = query(
        "select date_day::text from marts.fct_daily_consumption "
        "where is_drunk and is_in_last_30_days_of_data order by 1"
    )
    assert [r[0] for r in rows] == ref.q5_drunk_days_last_30()


def test_q6_weekly_series_from_marts():
    """Week-by-week, not just totals: catches a week-alignment bug that shifts units between neighbours."""
    rows = query("select iso_week_start, alcohol_units from marts.fct_weekly_consumption order by 1")
    weekly = ref.q6_weekly_units()
    # pandas labels ISO weeks by their Sunday end; SQL by their Monday start
    expected = {(end - pd.Timedelta(days=6)).date(): round(units, 2) for end, units in weekly.items()}
    assert {week: float(units) for week, units in rows} == expected


def test_q6_from_marts():
    ((weeks, over, avg),) = query(
        "select count(*), count(*) filter (where is_over_nhs_limit), round(avg(alcohol_units), 2) "
        "from marts.fct_weekly_consumption"
    )
    weekly = ref.q6_weekly_units()
    assert (weeks, over) == (len(weekly), int((weekly > ref.NHS_WEEKLY_UNITS).sum()))
    assert avg == Decimal(str(round(weekly.mean(), 2)))


def test_q7_from_marts():
    ((saved,),) = query("select round(sum(amount_saved), 2) from marts.fct_drink")
    assert saved == ref.q7_happy_hour_savings()
