"""Authenticated end-to-end smoke test for a deployed InkShelf service."""
from __future__ import annotations

import json
import secrets
from urllib.request import Request, urlopen

from core import auth
from core import db as store


BASE_URL = "https://4-3rail.top/api/inkshelf"


def request(path: str, token: str, *, method: str = "GET", body: bytes | None = None, headers=None):
    values = {"Cookie": f"{auth.SESSION_COOKIE}={token}"}
    values.update(headers or {})
    response = urlopen(Request(BASE_URL + path, data=body, headers=values, method=method), timeout=30)
    return response, response.read()


def main() -> None:
    admin = next(user for user in store.list_users() if user.get("active") and user.get("role") == "admin")
    token = secrets.token_urlsafe(32)
    book_id = ""
    store.create_session(token, str(admin["username"]), days=1)
    try:
        health, health_body = request("/health", token)
        assert health.status == 200 and json.loads(health_body)["authenticated"] is True

        payload = "InkShelf server smoke test · 可安全删除。".encode("utf-8")
        uploaded, uploaded_body = request(
            "/upload?name=inkshelf-smoke-test.txt",
            token,
            method="PUT",
            body=payload,
            headers={"Content-Type": "text/plain; charset=utf-8"},
        )
        assert uploaded.status == 201
        book_id = json.loads(uploaded_body)["book"]["id"]

        listing, listing_body = request("/books", token)
        assert listing.status == 200
        assert any(item["id"] == book_id for item in json.loads(listing_body)["books"])

        partial, partial_body = request(
            f"/books/{book_id}/file",
            token,
            headers={"Range": "bytes=0-7"},
        )
        assert partial.status == 206 and len(partial_body) == 8
        assert partial.headers.get("Accept-Ranges") == "bytes"

        progress_body = json.dumps({"progress": 0.5, "position": 1}).encode("utf-8")
        progress, _ = request(
            f"/progress/{book_id}",
            token,
            method="PUT",
            body=progress_body,
            headers={"Content-Type": "application/json"},
        )
        assert progress.status == 200

        deleted, _ = request(f"/books/{book_id}", token, method="DELETE")
        assert deleted.status == 200
        book_id = ""
        print("InkShelf server smoke test passed: auth, list, upload, byte range, progress, delete")
    finally:
        if book_id:
            try:
                request(f"/books/{book_id}", token, method="DELETE")
            except Exception:
                pass
        store.delete_session(token)


if __name__ == "__main__":
    main()
