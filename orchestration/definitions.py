"""Dagster: one job that runs dlt (Drive -> raw), then dbt build (staging -> core -> intermediate -> marts).

Asset keys are aligned so the lineage graph is continuous: dlt resource `bars` materialises
AssetKey(["juan_raw", "bars"]), which is exactly the key dbt uses for `source('juan_raw', 'bars')`.
"""

import sys
from collections.abc import Mapping
from pathlib import Path
from typing import Any

import dagster as dg
from dagster_dbt import DagsterDbtTranslator, DbtCliResource, DbtProject, dbt_assets
from dagster_dlt import DagsterDltResource, DagsterDltTranslator, dlt_assets
from dagster_dlt.translator import DltResourceTranslatorData

from ingestion.pipeline import build_pipeline, juan_drive_source

DBT_DIR = Path(__file__).resolve().parent.parent / "transform"
RAW_SOURCE = "juan_raw"
# The dbt CLI installed next to this interpreter (venv or container), whether or not it is on PATH.
DBT_EXECUTABLE = str(Path(sys.executable).parent / "dbt")

# dlt unnests bars[].stock[] into raw.bars__stock as part of the `bars` resource load. Dagster needs a
# distinct key per dbt source, so the child table is declared as its own asset downstream of `bars`.
bars_stock_spec = dg.AssetSpec(
    key=dg.AssetKey([RAW_SOURCE, "bars__stock"]),
    deps=[dg.AssetKey([RAW_SOURCE, "bars"])],
    group_name="ingestion",
    description="Child table written by the dlt `bars` load (bars[].stock[] unnested).",
)


class RawKeyDltTranslator(DagsterDltTranslator):
    def get_asset_spec(self, data: DltResourceTranslatorData) -> dg.AssetSpec:
        return (
            super()
            .get_asset_spec(data)
            .replace_attributes(key=dg.AssetKey([RAW_SOURCE, data.resource.name]), deps=[])
        )


class SourceAlignedDbtTranslator(DagsterDbtTranslator):
    def get_asset_key(self, dbt_resource_props: Mapping[str, Any]) -> dg.AssetKey:
        if dbt_resource_props["resource_type"] == "source":
            return dg.AssetKey([dbt_resource_props["source_name"], dbt_resource_props["name"]])
        return super().get_asset_key(dbt_resource_props)

    def get_group_name(self, dbt_resource_props: Mapping[str, Any]) -> str | None:
        # Group dbt assets by warehouse layer, so the lineage reads
        # ingestion -> staging -> core -> intermediate -> marts.
        return dbt_resource_props.get("schema") or super().get_group_name(dbt_resource_props)


dbt_project = DbtProject(project_dir=DBT_DIR, profiles_dir=DBT_DIR)
dbt_project.prepare_if_dev()  # `dagster dev` re-parses the manifest; images parse it at build time


@dlt_assets(
    dlt_source=juan_drive_source(),
    dlt_pipeline=build_pipeline(),
    name="juan_drive",
    group_name="ingestion",
    dagster_dlt_translator=RawKeyDltTranslator(),
)
def raw_assets(context: dg.AssetExecutionContext, dlt: DagsterDltResource):
    yield from dlt.run(context=context)


@dbt_assets(
    manifest=dbt_project.manifest_path,
    project=dbt_project,
    dagster_dbt_translator=SourceAlignedDbtTranslator(),
)
def dbt_models(context: dg.AssetExecutionContext, dbt: DbtCliResource):
    # dbt tests surface as Dagster asset checks, so a failing data test fails the run.
    yield from dbt.cli(["build"], context=context).stream()


elt_job = dg.define_asset_job(
    "juan_elt",
    selection=dg.AssetSelection.all(),
    description="Load raw JSON from Google Drive with dlt, then dbt build (models + tests).",
)

defs = dg.Definitions(
    assets=[raw_assets, bars_stock_spec, dbt_models],
    jobs=[elt_job],
    resources={
        "dlt": DagsterDltResource(),
        "dbt": DbtCliResource(project_dir=dbt_project, dbt_executable=DBT_EXECUTABLE),
    },
)
