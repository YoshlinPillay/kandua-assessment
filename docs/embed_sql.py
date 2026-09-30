"""Re-embed the Q1–Q7 analysis SQL into docs/ANSWERS.md between <!-- sql:NAME --> ... <!-- /sql --> markers.

Run with `make docs`. tests/test_answers_doc.py fails if the doc and transform/analyses/*.sql drift apart.
"""

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DOC = ROOT / "docs/ANSWERS.md"
ANALYSES = ROOT / "transform/analyses"
# The body may be empty or hold a previous embed. It never contains another opening marker, so a block can't
# swallow its neighbour (a bug in the first version of this script).
BLOCK = re.compile(r"<!-- sql:(?P<name>[a-z0-9_]+) -->(?:(?!<!-- sql:).)*?<!-- /sql -->", re.DOTALL)


def embed(text: str) -> str:
    def replace(match: re.Match) -> str:
        sql = (ANALYSES / f"{match['name']}.sql").read_text().rstrip()
        return f"<!-- sql:{match['name']} -->\n```sql\n{sql}\n```\n<!-- /sql -->"

    return BLOCK.sub(replace, text)


if __name__ == "__main__":
    DOC.write_text(embed(DOC.read_text()))
    print(f"embedded SQL into {DOC.relative_to(ROOT)}")
