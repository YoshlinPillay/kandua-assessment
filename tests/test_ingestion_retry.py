"""Google Drive sometimes answers 503 (it failed a CI run): downloads must retry with backoff, not fail."""

import http.server
import threading

from ingestion import drive_files


def test_download_retries_transient_5xx(monkeypatch):
    calls = {"n": 0}

    class FlakyDrive(http.server.BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802 - http.server API
            calls["n"] += 1
            if calls["n"] <= 2:
                self.send_response(503)
                self.end_headers()
                return
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"[]")

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(("127.0.0.1", 0), FlakyDrive)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    monkeypatch.setattr(drive_files, "DOWNLOAD_URL", f"http://127.0.0.1:{server.server_port}/?id={{file_id}}")
    try:
        assert drive_files.download("bars") == b"[]"
        assert calls["n"] == 3  # two 503s retried, third attempt succeeded
    finally:
        server.shutdown()
