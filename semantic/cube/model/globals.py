"""Generate Cube cubes at runtime from dbt. dbt YAML is the single semantic source (CLAUDE.md rule 4).

- Cubes, descriptions, metrics (-> measures) and joins: dbt **manifest** (Lightdash `meta` format).
- Dimension types come from the dbt **catalog** (real warehouse types from `dbt docs generate`).

`cube_dbt` was evaluated first (D-024): it emits no measures or joins, and types every column declared without
`data_type` as string. So this small generator replaces it. Pure functions below are unit-tested in
tests/test_cube_generator.py without a Cube runtime.
"""

import json
import os
import re

MART_PATH_PREFIX = "marts/"

# Lightdash metric type -> Cube measure type
MEASURE_TYPES = {
    "sum": "sum",
    "count": "count",
    "count_distinct": "count_distinct",
    "average": "avg",
    "max": "max",
    "min": "min",
}

# Postgres type (from dbt catalog) -> Cube dimension type
DIMENSION_TYPES = {
    "date": "time",
    "timestamp without time zone": "time",
    "timestamp with time zone": "time",
    "integer": "number",
    "bigint": "number",
    "smallint": "number",
    "numeric": "number",
    "double precision": "number",
    "boolean": "boolean",
}


class SafeString(str):
    """Marks generated YAML as safe so Cube's Jinja doesn't escape it."""

    is_safe = True


def _meta(node: dict) -> dict:
    return node.get("config", {}).get("meta") or node.get("meta") or {}


def _sql_literal(value) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int | float):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def _join_sql(sql_on: str, cube_name: str) -> str:
    """Lightdash `${model.col}` -> Cube `{CUBE}.col` for the cube itself, `{other}.col` otherwise."""

    def repl(match: re.Match) -> str:
        model, column = match.group(1), match.group(2)
        return f"{{CUBE}}.{column}" if model == cube_name else f"{{{model}}}.{column}"

    return re.sub(r"\$\{(\w+)\.(\w+)\}", repl, sql_on)


def _primary_keys(manifest: dict, model_name: str) -> set[str]:
    """Columns with both `unique` and `not_null` dbt tests are the model's primary key."""
    tests: dict[str, set[str]] = {}
    for node in manifest["nodes"].values():
        if node["resource_type"] != "test" or not node.get("test_metadata"):
            continue
        column = node["test_metadata"].get("kwargs", {}).get("column_name")
        tested_models = {dep.split(".")[-1] for dep in node.get("depends_on", {}).get("nodes", [])}
        if column and model_name in tested_models:
            tests.setdefault(column, set()).add(node["test_metadata"]["name"])
    return {col for col, names in tests.items() if {"unique", "not_null"} <= names}


def build_cubes(manifest: dict, catalog: dict) -> list[dict]:
    cubes = []
    for unique_id, node in sorted(manifest["nodes"].items()):
        if node["resource_type"] != "model" or not node["path"].startswith(MART_PATH_PREFIX):
            continue
        name = node["name"]
        catalog_columns = catalog["nodes"][unique_id]["columns"]
        yaml_columns = node.get("columns", {})
        # Several columns can be unique + not_null (e.g. bar_id and bar_name are both candidate keys).
        # The primary key is the first of them in table order, which is the surrogate id by convention.
        candidates = _primary_keys(manifest, name)
        ordered = sorted(catalog_columns.values(), key=lambda col: col["index"])
        pks = {next(col["name"] for col in ordered if col["name"] in candidates)} if candidates else set()

        dimensions = []
        for col_name, col in sorted(catalog_columns.items(), key=lambda kv: kv[1]["index"]):
            col_meta = _meta(yaml_columns.get(col_name, {}))
            dimension = {
                "name": col_name,
                "sql": f"{{CUBE}}.{col_name}",
                "type": DIMENSION_TYPES.get(col["type"].lower(), "string"),
            }
            description = yaml_columns.get(col_name, {}).get("description")
            if description:
                dimension["description"] = description
            if col_name in pks:
                dimension["primary_key"] = True
            if col_meta.get("dimension", {}).get("hidden"):
                dimension["public"] = False  # same visibility as in Lightdash
            dimensions.append(dimension)

        measures = []
        for col_name, col in yaml_columns.items():
            for metric_name, metric in _meta(col).get("metrics", {}).items():
                measure = {
                    "name": metric_name,
                    "type": MEASURE_TYPES[metric["type"]],
                    "title": metric.get("label", metric_name),
                    "description": metric.get("description", ""),
                }
                if measure["type"] != "count":
                    measure["sql"] = f"{{CUBE}}.{col_name}"
                filters = [
                    {"sql": f"{{CUBE}}.{field} = {_sql_literal(value)}"}
                    for condition in metric.get("filters", [])
                    for field, value in condition.items()
                ]
                if filters:
                    measure["filters"] = filters
                measures.append(measure)

        joins = [
            {
                "name": join["join"],
                "relationship": join.get("relationship", "many-to-one").replace("-", "_"),
                "sql": _join_sql(join["sql_on"], name),
            }
            for join in _meta(node).get("joins", [])
        ]

        cube = {
            "name": name,
            "sql_table": f"{node['schema']}.{node['alias'] or name}",
            "description": node.get("description", ""),
            "dimensions": dimensions,
        }
        if measures:
            cube["measures"] = measures
        if joins:
            cube["joins"] = joins
        cubes.append(cube)
    return cubes


def cubes_yaml(manifest: dict, catalog: dict) -> str:
    # JSON is valid YAML, so the standard library is enough: Cube's runtime has no PyYAML.
    return json.dumps({"cubes": build_cubes(manifest, catalog)}, ensure_ascii=False, indent=2)


try:  # Registered only inside the Cube runtime; plain import (tests) skips this.
    from cube import TemplateContext

    template = TemplateContext()

    @template.function("marts_cubes")
    def marts_cubes() -> str:
        with open(os.environ["DBT_MANIFEST_PATH"]) as m, open(os.environ["DBT_CATALOG_PATH"]) as c:
            return SafeString(cubes_yaml(json.load(m), json.load(c)))

except ImportError:
    pass
