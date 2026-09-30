"""docs/ANSWERS.md embeds the Q1–Q7 SQL. Fail if the doc and transform/analyses/*.sql ever drift apart."""

from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
ANALYSES = sorted((ROOT / "transform/analyses").glob("q*.sql"))


@pytest.mark.parametrize("sql_file", ANALYSES, ids=lambda p: p.stem)
def test_answers_doc_embeds_current_sql(sql_file):
    assert sql_file.read_text().rstrip() in (ROOT / "docs/ANSWERS.md").read_text()


def test_all_seven_questions_have_sql():
    assert len(ANALYSES) == 7
