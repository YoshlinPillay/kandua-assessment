"""Independent reference implementation of Q1–Q7: pandas straight from the raw JSON files.

This deliberately shares no code with dbt: it re-applies the human decisions itself (docs/decisions.md), so
SQL and pandas agreeing is evidence, not an echo. If an answer changes, both sides must change.
"""

import json
from decimal import ROUND_HALF_UP, Decimal
from functools import cache

import pandas as pd

from ingestion.drive_files import RAW_DIR, fetch_all

# D-008: Tiger's Milk Lager is missing from the catalog. Assumed to be a beer with 1.2 units.
ASSUMED_BEVERAGES = [{"name": "Tiger's Milk Lager", "type": "beer", "alcoholUnits": 1.2}]
DRUNK_UNITS = 14  # brief: Juan needs 14 units to get drunk
NHS_WEEKLY_UNITS = 14
HAPPY_HOUR_DISCOUNT = 0.5
LAST_N_DAYS = 30  # D-014: "last month" = the last 30 days of data


def _load(name: str):
    path = RAW_DIR / f"{name}.json"
    if not path.exists():
        fetch_all()
    return json.loads(path.read_text())


@cache
def drink_lines() -> pd.DataFrame:
    """One row per visit event (D-006) enriched with type, units and the bar's price."""
    events = pd.DataFrame(_load("visit_events"))
    catalog = pd.DataFrame(_load("beers") + ASSUMED_BEVERAGES).set_index("name")
    prices = pd.DataFrame([{"bar_name": b["barName"], **s} for b in _load("bars") for s in b["stock"]])
    prices = prices.rename(columns={"name": "beverage"})

    df = events.merge(prices, on=["bar_name", "beverage"], how="left")
    df["type"] = df.beverage.map(catalog["type"])
    df["units"] = df.drinks * df.beverage.map(catalog["alcoholUnits"])
    df["visited"] = pd.to_datetime(df.visited)
    return df


def q1_type_servings() -> dict[str, int]:
    return drink_lines().groupby("type").drinks.sum().astype(int).to_dict()


def q2_visits_per_bar() -> dict[str, int]:
    return drink_lines().bar_name.value_counts().to_dict()


def q3_beer_servings() -> dict[str, int]:
    beers = drink_lines().query("type == 'beer'")
    return beers.groupby("beverage").drinks.sum().astype(int).to_dict()


def q4_visits_without_drink() -> int:
    return int(drink_lines().beverage.isna().sum())


def q5_drunk_days_last_30() -> list[str]:
    df = drink_lines()
    end = df.visited.max()
    window = df[df.visited > end - pd.Timedelta(days=LAST_N_DAYS)]
    daily = window.groupby("visited").units.sum()
    return [d.strftime("%Y-%m-%d") for d in daily[daily >= DRUNK_UNITS].index]


def q6_weekly_units() -> pd.Series:
    """Units per ISO week (Monday start), including weeks with no drinking as 0."""
    df = drink_lines().set_index("visited")
    return df.units.resample("W-SUN").sum()  # W-SUN = weeks ending Sunday = ISO Monday-start weeks


def _cents(value: Decimal) -> Decimal:
    # Half-up to the cent (like Postgres numeric rounding). Python's round() is banker's rounding.
    return value.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)


def q7_happy_hour_savings() -> Decimal:
    """D-022: each happy-hour drink line's saving is rounded to the cent, like a bill, then summed."""
    hh = drink_lines().query("happy_hour == True")
    return sum(
        (
            _cents(Decimal(str(price)) * int(drinks) * Decimal(str(HAPPY_HOUR_DISCOUNT)))
            for price, drinks in zip(hh.price, hh.drinks, strict=True)
        ),
        Decimal("0"),
    )
