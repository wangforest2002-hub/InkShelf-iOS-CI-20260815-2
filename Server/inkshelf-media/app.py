from __future__ import annotations

import json
import os
import re
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse
from urllib.request import Request, urlopen


HOST = "127.0.0.1"
PORT = int(os.environ.get("INKSHELF_MEDIA_PORT", "8003"))
MAX_UPSTREAM_BYTES = 2_000_000
POST_PATTERN = re.compile(
    r"^https://(?:www\.|mobile\.)?(?:x\.com|twitter\.com)/([A-Za-z0-9_]{1,15})/status/(\d+)(?:[/?#].*)?$",
    re.IGNORECASE,
)


def normalize_photo_url(value: str) -> str:
    parsed = urlparse(value)
    if parsed.scheme != "https" or parsed.hostname != "pbs.twimg.com":
        raise ValueError("unsupported media host")
    query = parse_qs(parsed.query, keep_blank_values=True)
    query["name"] = ["orig"]
    return urlunparse((parsed.scheme, parsed.netloc, parsed.path, "", urlencode(query, doseq=True), ""))


def photo_format(photo: dict, media_url: str) -> str:
    declared = str(photo.get("format") or "").lower()
    if declared in {"jpg", "jpeg", "png", "webp"}:
        return "jpg" if declared == "jpeg" else declared
    query_format = parse_qs(urlparse(media_url).query).get("format", [""])[0].lower()
    if query_format in {"jpg", "jpeg", "png", "webp"}:
        return "jpg" if query_format == "jpeg" else query_format
    suffix = urlparse(media_url).path.rsplit(".", 1)[-1].lower()
    return suffix if suffix in {"jpg", "png", "webp"} else "jpg"


def resolve_post(post_url: str) -> dict:
    match = POST_PATTERN.match(post_url.strip())
    if not match:
        raise ValueError("请提供完整的公开 X 帖子链接。")
    username, post_id = match.groups()
    canonical_url = f"https://x.com/{username}/status/{post_id}"
    upstream_url = f"https://api.fxtwitter.com/{username}/status/{post_id}"
    request = Request(
        upstream_url,
        headers={
            "Accept": "application/json",
            "User-Agent": "InkShelf/1.9 (personal media importer; https://4-3rail.top/inkshelf-update/)",
        },
    )
    try:
        with urlopen(request, timeout=15) as response:
            raw = response.read(MAX_UPSTREAM_BYTES + 1)
    except HTTPError as error:
        raise LookupError("这条帖子暂时无法读取，可能已删除或不是公开内容。") from error
    except URLError as error:
        raise ConnectionError("X 图片解析服务暂时不可用，请稍后再试。") from error
    if len(raw) > MAX_UPSTREAM_BYTES:
        raise LookupError("帖子返回内容过大，已停止读取。")
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise LookupError("X 返回了无法识别的帖子内容。") from error

    post = payload.get("tweet") or payload.get("status")
    if not isinstance(post, dict):
        raise LookupError(str(payload.get("message") or "没有找到这条公开帖子。"))
    author = post.get("author") if isinstance(post.get("author"), dict) else {}
    media = post.get("media") if isinstance(post.get("media"), dict) else {}
    photos = media.get("photos") if isinstance(media.get("photos"), list) else []
    if not photos and isinstance(post.get("quote"), dict):
        quote_media = post["quote"].get("media") if isinstance(post["quote"].get("media"), dict) else {}
        photos = quote_media.get("photos") if isinstance(quote_media.get("photos"), list) else []

    normalized = []
    for index, photo in enumerate(photos[:20]):
        if not isinstance(photo, dict) or not isinstance(photo.get("url"), str):
            continue
        try:
            media_url = normalize_photo_url(photo["url"])
        except ValueError:
            continue
        normalized.append(
            {
                "id": str(photo.get("id") or index + 1),
                "url": media_url,
                "width": max(1, int(photo.get("width") or 1)),
                "height": max(1, int(photo.get("height") or 1)),
                "format": photo_format(photo, media_url),
                "alt_text": str(photo.get("altText") or photo.get("alt_text") or "") or None,
            }
        )
    if not normalized:
        raise LookupError("这条帖子里没有可导入的静态图片。")
    return {
        "post_id": str(post.get("id") or post_id),
        "post_url": str(post.get("url") or canonical_url),
        "author_name": str(author.get("name") or username),
        "username": str(author.get("screen_name") or author.get("username") or username),
        "text": str(post.get("text") or ""),
        "images": normalized,
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "InkShelfMedia/1.0"

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self.send_json(200, {"status": "ok", "service": "inkshelf-media"})
            return
        if parsed.path != "/x/resolve":
            self.send_json(404, {"message": "not found"})
            return
        values = parse_qs(parsed.query).get("url", [])
        if not values:
            self.send_json(400, {"message": "缺少 X 帖子链接。"})
            return
        try:
            self.send_json(200, resolve_post(values[0]))
        except ValueError as error:
            self.send_json(400, {"message": str(error)})
        except LookupError as error:
            self.send_json(404, {"message": str(error)})
        except ConnectionError as error:
            self.send_json(503, {"message": str(error)})
        except Exception:
            self.send_json(500, {"message": "图片通道暂时遇到问题，请稍后再试。"})

    def send_json(self, status: int, value: dict) -> None:
        data = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("X-Robots-Tag", "noindex, nofollow")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"{self.address_string()} - {fmt % args}", flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()

