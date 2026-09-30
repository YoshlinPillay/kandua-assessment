"""The ERM (docs/erm/transactional.dbml) is the source of truth for schema `core` (CLAUDE.md rule 3).

Two layers of drift detection:
- static: DBML vs the dbt contracts in transform/models/core/_core.yml (no database needed, runs in lint CI)
- live:   DBML vs the constraints Postgres actually created (skipped when the warehouse is unreachable)
"""

from pathlib import Path

import yaml
from pydbml import PyDBML

from tests.warehouse import connect_or_skip

ROOT = Path(__file__).resolve().parent.parent
DBML = PyDBML((ROOT / "docs/erm/transactional.dbml").read_text())
CORE_YML = yaml.safe_load((ROOT / "transform/models/core/_core.yml").read_text())


def _norm_type(t: str) -> str:
    return t.replace(" ", "").lower()


def dbml_schema() -> dict:
    """{table: {columns: {name: type}, pk, not_null, unique_sets, fks: {col: (table, col)}}}"""
    out = {}
    for t in DBML.tables:
        cols = {c.name: _norm_type(str(c.type)) for c in t.columns}
        unique_sets = {frozenset([c.name]) for c in t.columns if c.unique}
        unique_sets |= {frozenset(str(c.name) for c in i.subjects) for i in t.indexes if i.unique}
        out[t.name] = {
            "columns": cols,
            "pk": frozenset(c.name for c in t.columns if c.pk),
            "not_null": frozenset(c.name for c in t.columns if c.not_null or c.pk),
            "unique_sets": unique_sets,
            "fks": {},
        }
    for r in DBML.refs:
        src, dst = r.col1[0], r.col2[0]
        out[src.table.name]["fks"][src.name] = (dst.table.name, dst.name)
    return out


def contract_schema() -> dict:
    out = {}
    for m in CORE_YML["models"]:
        cols, pk, nn, uniq, fks = {}, set(), set(), set(), {}
        for c in m["columns"]:
            cols[c["name"]] = _norm_type(c["data_type"])
            for con in c.get("constraints", []):
                kind = con["type"]
                if kind == "primary_key":
                    pk.add(c["name"])
                    nn.add(c["name"])
                elif kind == "not_null":
                    nn.add(c["name"])
                elif kind == "unique":
                    uniq.add(frozenset([c["name"]]))
                elif kind == "foreign_key":
                    target = con["to"].split("'")[1]  # ref('bar') -> bar
                    fks[c["name"]] = (target, con["to_columns"][0])
        for con in m.get("constraints", []):
            if con["type"] == "unique":
                uniq.add(frozenset(con["columns"]))
        out[m["name"]] = {
            "columns": cols,
            "pk": frozenset(pk),
            "not_null": frozenset(nn),
            "unique_sets": uniq,
            "fks": fks,
        }
    return out


def test_dbml_matches_dbt_contracts():
    assert contract_schema() == dbml_schema()


PG_SCHEMA_SQL = """
select c.table_name, c.column_name, c.is_nullable,
       case when c.data_type = 'numeric'
            then format('numeric(%s,%s)', c.numeric_precision, c.numeric_scale)
            else c.data_type end as data_type
from information_schema.columns c
where c.table_schema = 'core'
"""

PG_CONSTRAINTS_SQL = """
select con.contype, rel.relname as table_name,
       array(select att.attname from unnest(con.conkey) k
             join pg_attribute att on att.attrelid = con.conrelid and att.attnum = k order by att.attname)
         as columns,
       frel.relname as ref_table,
       array(select att.attname from unnest(con.confkey) k
             join pg_attribute att on att.attrelid = con.confrelid and att.attnum = k) as ref_columns
from pg_constraint con
join pg_class rel on rel.oid = con.conrelid
join pg_namespace ns on ns.oid = rel.relnamespace
left join pg_class frel on frel.oid = con.confrelid
where ns.nspname = 'core' and con.contype in ('p', 'u', 'f')
"""

PG_TYPE_ALIASES = {"integer": "integer", "boolean": "boolean", "text": "text", "uuid": "uuid", "date": "date"}


def test_database_matches_dbml():
    with connect_or_skip() as conn:
        cols = conn.execute(PG_SCHEMA_SQL).fetchall()
        cons = conn.execute(PG_CONSTRAINTS_SQL).fetchall()

    live: dict = {}
    for table, column, nullable, dtype in cols:
        t = live.setdefault(
            table, {"columns": {}, "pk": set(), "not_null": set(), "unique_sets": set(), "fks": {}}
        )
        t["columns"][column] = PG_TYPE_ALIASES.get(dtype, dtype)
        if nullable == "NO":
            t["not_null"].add(column)
    for contype, table, columns, ref_table, ref_columns in cons:
        t = live[table]
        if contype == "p":
            t["pk"] = set(columns)
        elif contype == "u":
            t["unique_sets"].add(frozenset(columns))
        elif contype == "f":
            t["fks"][columns[0]] = (ref_table, ref_columns[0])
    for t in live.values():
        t["pk"], t["not_null"] = frozenset(t["pk"]), frozenset(t["not_null"])

    assert live == dbml_schema()


ANALYTICAL = PyDBML((ROOT / "docs/erm/analytical.dbml").read_text())


def test_marts_match_analytical_dbml():
    """Columns and types of the star schema must match docs/erm/analytical.dbml (reviewer finding, P5)."""
    expected = {t.name: {c.name: _norm_type(str(c.type)) for c in t.columns} for t in ANALYTICAL.tables}
    with connect_or_skip() as conn:
        rows = conn.execute(PG_SCHEMA_SQL.replace("'core'", "'marts'")).fetchall()
    live: dict = {}
    for table, column, _nullable, dtype in rows:
        live.setdefault(table, {})[column] = PG_TYPE_ALIASES.get(dtype, dtype)
    assert live == expected
