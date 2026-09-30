"""The reviewer/BI role must be read-only on core + marts and blind to raw/staging (security.md)."""

import psycopg
import pytest

from tests.warehouse import connect_or_skip


def test_reader_can_select_core():
    with connect_or_skip("reader") as conn:
        assert conn.execute("select count(*) from core.visit").fetchone()[0] > 0


def test_reader_cannot_write_core():
    with connect_or_skip("reader") as conn, pytest.raises(psycopg.errors.InsufficientPrivilege):
        conn.execute("insert into core.drinker (drinker_id, name) values ('x', 'intruder')")


@pytest.mark.parametrize("table", ["raw.visit_events", "staging.stg_juan__visit_events"])
def test_reader_cannot_see_raw_or_staging(table):
    with connect_or_skip("reader") as conn, pytest.raises(psycopg.errors.InsufficientPrivilege):
        conn.execute(f"select 1 from {table} limit 1")  # noqa: S608 (fixed table names)
