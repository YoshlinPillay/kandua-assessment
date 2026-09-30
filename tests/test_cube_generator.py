"""The Cube model is generated from dbt (CLAUDE.md rule 4). These tests need no Cube runtime: they run the
generator on the real dbt manifest + catalog and check nothing is lost or invented on the way."""

import importlib.util
import json
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TARGET = ROOT / "transform/target"
CUBE_MODEL = ROOT / "semantic/cube/model"

_spec = importlib.util.spec_from_file_location("cube_globals", CUBE_MODEL / "globals.py")
generator = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(generator)


@pytest.fixture(scope="module")
def dbt_artifacts():
    if not (TARGET / "catalog.json").exists():
        pytest.skip("run `make pipeline` first (needs manifest.json + catalog.json)")
    return json.loads((TARGET / "manifest.json").read_text()), json.loads(
        (TARGET / "catalog.json").read_text()
    )


def dbt_metrics(manifest: dict) -> dict[str, set[str]]:
    out: dict[str, set[str]] = {}
    for node in manifest["nodes"].values():
        if node["resource_type"] == "model" and node["path"].startswith("marts/"):
            out[node["name"]] = {
                metric
                for col in node["columns"].values()
                for metric in generator._meta(col).get("metrics", {})
            }
    return out


def test_every_dbt_metric_becomes_exactly_one_cube_measure(dbt_artifacts):
    manifest, catalog = dbt_artifacts
    cubes = {
        c["name"]: {m["name"] for m in c.get("measures", [])} for c in generator.build_cubes(*dbt_artifacts)
    }
    assert cubes == dbt_metrics(manifest)


def test_every_cube_has_exactly_one_primary_key(dbt_artifacts):
    for cube in generator.build_cubes(*dbt_artifacts):
        assert len([d for d in cube["dimensions"] if d.get("primary_key")]) == 1, cube["name"]


def test_dimension_types_come_from_the_warehouse(dbt_artifacts):
    cubes = {
        c["name"]: {d["name"]: d["type"] for d in c["dimensions"]}
        for c in generator.build_cubes(*dbt_artifacts)
    }
    assert cubes["fct_drink"]["date_day"] == "time"
    assert cubes["fct_drink"]["quantity"] == "number"
    assert cubes["fct_drink"]["is_happy_hour"] == "boolean"
    assert cubes["dim_bar"]["bar_name"] == "string"


def test_output_is_json_and_therefore_valid_yaml(dbt_artifacts):
    assert "cubes" in json.loads(generator.cubes_yaml(*dbt_artifacts))


def test_join_sql_translation():
    assert (
        generator._join_sql("${fct_drink.bar_id} = ${dim_bar.bar_id}", "fct_drink")
        == "{CUBE}.bar_id = {dim_bar}.bar_id"
    )


def test_no_hand_written_static_cubes():
    static = [p.name for p in CUBE_MODEL.rglob("*") if p.suffix in {".yml", ".yaml", ".js"}]
    assert static == [], "cubes must be generated from dbt YAML, not hand-written"
