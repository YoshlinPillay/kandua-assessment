"""Read-only client for the Cube REST API: the chat agent's only window onto the data.

The agent never writes SQL. It can list governed metrics (/meta) and run metric queries (/load), and
every member it names is checked against the catalogue first, so a hallucinated metric fails fast.
"""

import os
import time
from dataclasses import dataclass, field

import jwt
import requests


class CubeQueryError(ValueError):
    """The query is invalid (unknown member, bad shape). Returned to the model as a tool error."""


@dataclass
class CubeClient:
    url: str = field(
        default_factory=lambda: os.environ.get("CUBE_URL", "http://localhost:4000/cubejs-api/v1")
    )
    secret: str = field(default_factory=lambda: os.environ["CUBEJS_API_SECRET"])
    timeout: int = 30
    _catalogue: dict | None = None

    def _headers(self) -> dict:
        token = jwt.encode({"exp": int(time.time()) + 300}, self.secret, algorithm="HS256")
        return {"Authorization": token}

    def catalogue(self) -> dict:
        """Compact view of /meta for the model: public measures and dimensions per cube, with descriptions."""
        if self._catalogue is None:
            meta = requests.get(f"{self.url}/meta", headers=self._headers(), timeout=self.timeout)
            meta.raise_for_status()
            self._catalogue = {
                cube["name"]: {
                    "description": cube.get("description", ""),
                    "measures": {
                        m["name"]: f"{m.get('title', '')}: {m.get('description', '')}".strip(": ")
                        for m in cube.get("measures", [])
                    },
                    "dimensions": {
                        d["name"]: f"{d['type']}. {d.get('description', '')}".strip(". ")
                        for d in cube.get("dimensions", [])
                        if d.get("public", True)
                    },
                }
                for cube in meta.json()["cubes"]
            }
        return self._catalogue

    def _known_members(self) -> tuple[set[str], set[str]]:
        cat = self.catalogue()
        measures = {m for cube in cat.values() for m in cube["measures"]}
        dimensions = {d for cube in cat.values() for d in cube["dimensions"]}
        return measures, dimensions

    def validate(self, query: dict) -> None:
        measures, dimensions = self._known_members()
        unknown = [m for m in query.get("measures", []) if m not in measures]
        unknown += [d for d in query.get("dimensions", []) if d not in dimensions]
        unknown += [
            f["member"] for f in query.get("filters", []) if f.get("member") not in dimensions | measures
        ]
        unknown += [
            t["dimension"] for t in query.get("timeDimensions", []) if t.get("dimension") not in dimensions
        ]
        unknown += [k for k in query.get("order", {}) if k not in measures | dimensions]
        if unknown:
            raise CubeQueryError(f"Unknown members {unknown}. Call list_metrics and use exact names.")
        if not query.get("measures") and not query.get("dimensions"):
            raise CubeQueryError("A query needs at least one measure or dimension.")

    def load(self, query: dict) -> list[dict]:
        self.validate(query)
        response = requests.post(
            f"{self.url}/load", json={"query": query}, headers=self._headers(), timeout=self.timeout
        )
        if response.status_code == 400:
            raise CubeQueryError(response.json().get("error", response.text))
        response.raise_for_status()
        return response.json()["data"]
