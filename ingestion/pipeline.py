"""dlt pipeline: Google Drive JSON files -> Postgres schema `raw`.

dlt infers column types, unnests `bars[].stock[]` into a child table (`raw.bars__stock`) and records load
metadata (`_dlt_load_id`, `_dlt_id`). Data is loaded as-is; all cleaning happens in dbt staging
(CLAUDE.md rule 2).
"""

import json
import os

import dlt

from ingestion.drive_files import download


def _records(name: str):
    yield from json.loads(download(name))


@dlt.source(name="juan_drive")
def juan_drive_source():
    # The source files are full snapshots, so each load replaces the previous one.
    @dlt.resource(name="bars", write_disposition="replace")
    def bars():
        yield from _records("bars")

    @dlt.resource(name="beverages", write_disposition="replace")
    def beverages():
        # The source file is called beers.json but holds every beverage type (docs/data_profile.md).
        yield from _records("beers")

    @dlt.resource(
        name="visit_events",
        write_disposition="replace",
        primary_key="uuid",
        columns={"visited": {"data_type": "text"}},  # keep the raw string; typed in staging
    )
    def visit_events():
        yield from _records("visit_events")

    # Barcodes have leading zeros: pin to text so no type inference can ever turn them into numbers.
    beverages.apply_hints(columns={"codebar": {"data_type": "text"}})
    return bars, beverages, visit_events


def postgres_credentials() -> str:
    env = os.environ
    return (
        f"postgresql://{env['POSTGRES_ADMIN_USER']}:{env['POSTGRES_ADMIN_PASSWORD']}"
        f"@{env.get('POSTGRES_HOST', 'localhost')}:{env.get('POSTGRES_PORT', '5433')}/{env['POSTGRES_DB']}"
    )


def build_pipeline() -> dlt.Pipeline:
    return dlt.pipeline(
        pipeline_name="juan_drive",
        destination=dlt.destinations.postgres(credentials=postgres_credentials()),
        dataset_name="raw",
    )


if __name__ == "__main__":
    info = build_pipeline().run(juan_drive_source())
    print(info)
