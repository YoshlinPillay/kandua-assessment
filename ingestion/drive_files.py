"""Location of the raw source files: a public Google Drive folder provided by Kandua.

The dlt pipeline (ingestion/pipeline.py) and the profiling/cross-check tests both use this module,
so there is exactly one definition of "the raw data".
"""

from pathlib import Path

from dlt.sources.helpers.requests import Client

DRIVE_FOLDER_ID = "1Nb-Sx0kav9I9J8denMFWu-wUeUnJRaSc"

# File IDs taken from the folder's public embedded view.
DRIVE_FILES: dict[str, str] = {
    "bars": "1JtOaSlUxkj46FRJVpJmdOyzHuLPqBX-D",
    "beers": "1DOS7rBX3PgtLlbt4hE_kiTI0cFMowJgz",
    "visit_events": "1heShYQQRP7Bbyl35cG-Qzz8OoXwRSlOy",
}

DOWNLOAD_URL = "https://drive.usercontent.google.com/download?id={file_id}&export=download"
RAW_DIR = Path(__file__).resolve().parent.parent / "data" / "raw"

# dlt's requests client retries 429/5xx and connection errors with exponential backoff. Google Drive returns
# occasional 503s (one failed a CI run), so a single attempt isn't good enough for a pipeline.
_http = Client(
    request_timeout=60, request_max_attempts=6, request_backoff_factor=2, request_max_retry_delay=60
)


def download(name: str) -> bytes:
    """Download one raw file's bytes from Google Drive (retried with backoff on 429/5xx)."""
    return _http.session.get(DOWNLOAD_URL.format(file_id=DRIVE_FILES[name])).content


def fetch_all(dest: Path = RAW_DIR) -> list[Path]:
    """Cache every raw file locally (data/raw is gitignored and treated as immutable)."""
    dest.mkdir(parents=True, exist_ok=True)
    paths = []
    for name in DRIVE_FILES:
        path = dest / f"{name}.json"
        path.write_bytes(download(name))
        paths.append(path)
    return paths


if __name__ == "__main__":
    for p in fetch_all():
        print(f"{p.relative_to(RAW_DIR.parent.parent)}  {p.stat().st_size} bytes")
