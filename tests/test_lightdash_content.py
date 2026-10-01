"""Every field a chart references (lightdash/charts/*.yml) must exist in the semantic layer (dbt YAML).

Lightdash only exposes columns declared in the model YAML, so a chart referencing an undeclared column breaks
on the dashboard ("unknown field id"). That happened once (units-by-weekday → dim_date.iso_day_of_week);
this test makes it impossible to ship again. No Lightdash instance needed.
"""

import json
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "transform/target/manifest.json"
CHARTS = sorted((ROOT / "lightdash/charts").glob("*.yml"))


def semantic_fields() -> set[str]:
    """Lightdash field ids: <model>_<column>, <model>_<column>_<interval>, <model>_<metric>."""
    if not MANIFEST.exists():
        pytest.skip("run `make dbt ARGS=parse` first")
    fields = set()
    for node in json.loads(MANIFEST.read_text())["nodes"].values():
        if node["resource_type"] != "model" or not node["path"].startswith("marts/"):
            continue
        for column, spec in node["columns"].items():
            meta = spec.get("config", {}).get("meta") or spec.get("meta") or {}
            fields.add(f"{node['name']}_{column}")
            for interval in meta.get("dimension", {}).get("time_intervals", []):
                fields.add(f"{node['name']}_{column}_{interval.lower()}")
            for metric in meta.get("metrics", {}):
                fields.add(f"{node['name']}_{metric}")
    return fields


@pytest.mark.parametrize("chart", CHARTS, ids=lambda p: p.stem)
def test_chart_fields_exist_in_semantic_layer(chart):
    query = yaml.safe_load(chart.read_text())["metricQuery"]
    used = set(query["dimensions"]) | set(query["metrics"]) | {s["fieldId"] for s in query["sorts"]}
    assert used - semantic_fields() == set()


def test_dashboard_tiles_reference_existing_charts():
    slugs = {yaml.safe_load(p.read_text())["slug"] for p in CHARTS}
    for dashboard in (ROOT / "lightdash/dashboards").glob("*.yml"):
        tiles = yaml.safe_load(dashboard.read_text())["tiles"]
        referenced = {t["properties"]["chartSlug"] for t in tiles if t["type"] == "saved_chart"}
        assert referenced - slugs == set(), dashboard.name
