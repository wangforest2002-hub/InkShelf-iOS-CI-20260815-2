"""End-to-end smoke test for the standalone, open InkShelf service."""
from __future__ import annotations

import json
from urllib.request import Request, urlopen


BASE_URL = "https://4-3rail.top/inkshelf-api"


def request(path: str, *, method: str = "GET", body: bytes | None = None, headers=None):
    response = urlopen(
        Request(BASE_URL + path, data=body, headers=headers or {}, method=method),
        timeout=30,
    )
    return response, response.read()


def main() -> None:
    book_id = ""
    try:
        health, health_body = request("/health")
        status = json.loads(health_body)
        assert health.status == 200 and status["standalone"] is True and status["access"] == "open"

        payload = "InkShelf standalone smoke test · 可安全删除。".encode("utf-8")
        uploaded, uploaded_body = request(
            "/upload?name=inkshelf-smoke-test.txt",
            method="PUT",
            body=payload,
            headers={"Content-Type": "text/plain; charset=utf-8"},
        )
        assert uploaded.status == 201
        book_id = json.loads(uploaded_body)["book"]["id"]

        listing, listing_body = request("/books")
        assert listing.status == 200
        assert any(item["id"] == book_id for item in json.loads(listing_body)["books"])

        partial, partial_body = request(
            f"/books/{book_id}/file",
            headers={"Range": "bytes=0-7"},
        )
        assert partial.status == 206 and len(partial_body) == 8
        assert partial.headers.get("Accept-Ranges") == "bytes"

        progress_body = json.dumps({"progress": 0.5, "position": 1}).encode("utf-8")
        progress, _ = request(
            f"/progress/{book_id}",
            method="PUT",
            body=progress_body,
            headers={"Content-Type": "application/json"},
        )
        assert progress.status == 200

        deleted, _ = request(f"/books/{book_id}", method="DELETE")
        assert deleted.status == 200
        book_id = ""
        print("InkShelf standalone smoke test passed: list, upload, byte range, progress, delete")
    finally:
        if book_id:
            try:
                request(f"/books/{book_id}", method="DELETE")
            except Exception:
                pass


if __name__ == "__main__":
    main()
