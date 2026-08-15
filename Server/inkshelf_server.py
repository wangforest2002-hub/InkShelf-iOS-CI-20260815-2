"""Standalone InkShelf remote-library service.

The service intentionally runs on a separate loopback port. Nginx exposes only
``/inkshelf-api/``. It has its own metadata and storage, does not import or query
document-center, and intentionally has no login. Book files are stored
byte-for-byte without conversion.
"""
from __future__ import annotations

import hashlib
import io
import json
import mimetypes
import os
import re
import shutil
import subprocess
import threading
import uuid
import zipfile
from datetime import datetime
from email.utils import formatdate
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, unquote, urlparse

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
BOOK_DIR = DATA_DIR / "books"
COVER_DIR = DATA_DIR / "covers"
METADATA_PATH = DATA_DIR / "library.json"
PROGRESS_PATH = DATA_DIR / "progress.json"
HOST = os.environ.get("INKSHELF_HOST", "127.0.0.1")
PORT = int(os.environ.get("INKSHELF_PORT", "8001"))
MAX_UPLOAD_SIZE = int(os.environ.get("INKSHELF_MAX_UPLOAD_SIZE", str(8 * 1024**3)))
STREAM_CHUNK_SIZE = 1024 * 1024
BOOK_ID_PATTERN = re.compile(r"^[a-f0-9]{16}$")
SUPPORTED_SUFFIXES = {
    ".pdf", ".cbz", ".zip", ".jpg", ".jpeg", ".png", ".webp", ".gif",
    ".tif", ".tiff", ".bmp", ".heic", ".avif", ".epub", ".txt", ".html",
    ".htm", ".md", ".markdown", ".rtf", ".fb2",
}
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".tif", ".tiff", ".bmp"}
ARCHIVE_SUFFIXES = {".cbz", ".zip", ".epub"}
metadata_lock = threading.RLock()

try:
    from PIL import Image, ImageOps
except ImportError:
    Image = None
    ImageOps = None


def now_iso() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def ensure_storage() -> None:
    BOOK_DIR.mkdir(parents=True, exist_ok=True)
    COVER_DIR.mkdir(parents=True, exist_ok=True)
    if not METADATA_PATH.exists():
        METADATA_PATH.write_text("[]", encoding="utf-8")
    if not PROGRESS_PATH.exists():
        PROGRESS_PATH.write_text("{}", encoding="utf-8")


def read_json_file(path: Path, fallback):
    ensure_storage()
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return fallback


def write_json_file(path: Path, value) -> None:
    data = json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(data, encoding="utf-8")
    temp.replace(path)


def load_books() -> list[dict]:
    with metadata_lock:
        records = read_json_file(METADATA_PATH, [])
        return records if isinstance(records, list) else []


def save_books(records: list[dict]) -> None:
    with metadata_lock:
        write_json_file(METADATA_PATH, records)


def safe_filename(value: str) -> str:
    name = Path(str(value or "")).name.strip().replace("\x00", "")
    return name[:240]


def clean_book_id(value: str) -> str:
    candidate = str(value or "").strip().lower()
    return candidate if BOOK_ID_PATTERN.fullmatch(candidate) else ""


def find_book(book_id: str) -> dict | None:
    safe_id = clean_book_id(book_id)
    if not safe_id:
        return None
    return next((item for item in load_books() if str(item.get("id")) == safe_id), None)


def stored_path(record: dict) -> Path:
    return BOOK_DIR / Path(str(record.get("stored_name", ""))).name


def public_book(record: dict) -> dict:
    book_id = str(record.get("id", ""))
    progress = read_json_file(PROGRESS_PATH, {}).get(book_id)
    result = {
        key: record.get(key)
        for key in ("id", "name", "size", "format", "content_type", "imported_at", "modified_at")
    }
    result.update(
        {
            "download_url": f"/inkshelf-api/books/{quote(book_id)}/file",
            "cover_url": f"/inkshelf-api/books/{quote(book_id)}/cover",
            "progress": progress,
        }
    )
    return result


def generate_cover(record: dict) -> Path | None:
    if Image is None or ImageOps is None:
        return None
    book_id = str(record.get("id", ""))
    target = COVER_DIR / f"{book_id}.jpg"
    if target.exists():
        return target
    source = stored_path(record)
    if not source.exists():
        return None
    suffix = source.suffix.lower()
    image = None
    try:
        if suffix in IMAGE_SUFFIXES:
            image = Image.open(source)
        elif suffix in ARCHIVE_SUFFIXES:
            with zipfile.ZipFile(source) as archive:
                names = [
                    name for name in archive.namelist()
                    if Path(name).suffix.lower() in IMAGE_SUFFIXES and not name.endswith("/")
                ]
                if not names:
                    return None
                names.sort(key=lambda name: ("cover" not in name.lower(), name.lower()))
                info = archive.getinfo(names[0])
                if info.file_size > 40 * 1024**2:
                    return None
                image = Image.open(io.BytesIO(archive.read(info)))
        elif suffix == ".pdf" and shutil.which("pdftoppm"):
            base = COVER_DIR / f".{book_id}-render"
            subprocess.run(
                ["pdftoppm", "-f", "1", "-singlefile", "-jpeg", "-scale-to", "900", str(source), str(base)],
                check=True,
                timeout=30,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            rendered = base.with_suffix(".jpg")
            if rendered.exists():
                image = Image.open(rendered)
        if image is None:
            return None
        image = ImageOps.exif_transpose(image)
        image.thumbnail((720, 960))
        if image.mode not in {"RGB", "L"}:
            image = image.convert("RGB")
        temp = target.with_suffix(".tmp")
        image.save(temp, "JPEG", quality=82, optimize=True)
        temp.replace(target)
        return target
    except Exception:
        return None
    finally:
        rendered = COVER_DIR / f".{book_id}-render.jpg"
        rendered.unlink(missing_ok=True)
        if image is not None:
            try:
                image.close()
            except Exception:
                pass


class InkShelfHandler(BaseHTTPRequestHandler):
    server_version = "InkShelfLibrary/1.0"

    def log_message(self, format: str, *args) -> None:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"[{timestamp}] {self.client_address[0]} {format % args}")

    def send_json(self, payload: dict | list, status: HTTPStatus = HTTPStatus.OK) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(data)

    def send_error_json(self, status: HTTPStatus, message: str) -> None:
        self.send_json({"error": message}, status)

    def read_small_json(self) -> dict:
        length = int(self.headers.get("Content-Length", "0"))
        if length < 0 or length > 64 * 1024:
            raise ValueError("请求内容过大")
        body = self.rfile.read(length)
        value = json.loads(body.decode("utf-8")) if body else {}
        if not isinstance(value, dict):
            raise ValueError("JSON 格式不正确")
        return value

    def do_HEAD(self) -> None:
        parsed = urlparse(self.path)
        match = re.fullmatch(r"/inkshelf-api/books/([^/]+)/file", unquote(parsed.path))
        if match:
            self.send_book_file(match.group(1), send_body=False)
            return
        self.send_error_json(HTTPStatus.NOT_FOUND, "接口不存在")

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if path == "/inkshelf-api/health":
            self.send_json({"ok": True, "version": "1.1", "access": "open", "standalone": True})
            return
        if path == "/inkshelf-api/books":
            records = []
            for item in load_books():
                file_path = stored_path(item)
                if file_path.exists() and file_path.is_file():
                    current = dict(item)
                    current["size"] = file_path.stat().st_size
                    records.append(public_book(current))
            records.sort(key=lambda item: str(item.get("modified_at", "")), reverse=True)
            self.send_json({"books": records, "count": len(records)})
            return
        file_match = re.fullmatch(r"/inkshelf-api/books/([^/]+)/file", path)
        if file_match:
            self.send_book_file(file_match.group(1), send_body=True)
            return
        cover_match = re.fullmatch(r"/inkshelf-api/books/([^/]+)/cover", path)
        if cover_match:
            self.send_book_cover(cover_match.group(1))
            return
        self.send_error_json(HTTPStatus.NOT_FOUND, "接口不存在")

    def do_PUT(self) -> None:
        parsed = urlparse(self.path)
        path = unquote(parsed.path)
        if path == "/inkshelf-api/upload":
            self.receive_upload(parse_qs(parsed.query).get("name", [""])[0])
            return
        match = re.fullmatch(r"/inkshelf-api/progress/([^/]+)", path)
        if match:
            self.update_progress(match.group(1))
            return
        self.send_error_json(HTTPStatus.NOT_FOUND, "接口不存在")

    def do_DELETE(self) -> None:
        parsed = urlparse(self.path)
        match = re.fullmatch(r"/inkshelf-api/books/([^/]+)", unquote(parsed.path))
        if not match:
            self.send_error_json(HTTPStatus.NOT_FOUND, "接口不存在")
            return
        book_id = clean_book_id(match.group(1))
        records = load_books()
        target = next((item for item in records if item.get("id") == book_id), None)
        if target is None:
            self.send_error_json(HTTPStatus.NOT_FOUND, "书籍不存在")
            return
        stored_path(target).unlink(missing_ok=True)
        (COVER_DIR / f"{book_id}.jpg").unlink(missing_ok=True)
        save_books([item for item in records if item.get("id") != book_id])
        with metadata_lock:
            all_progress = read_json_file(PROGRESS_PATH, {})
            all_progress.pop(book_id, None)
            write_json_file(PROGRESS_PATH, all_progress)
        self.send_json({"deleted": book_id})

    def receive_upload(self, raw_name: str) -> None:
        name = safe_filename(raw_name or self.headers.get("X-Book-Filename", ""))
        suffix = Path(name).suffix.lower()
        if not name or suffix not in SUPPORTED_SUFFIXES:
            self.send_error_json(HTTPStatus.BAD_REQUEST, "不支持这种书籍格式")
            return
        try:
            length = int(self.headers.get("Content-Length", "-1"))
        except ValueError:
            length = -1
        if length < 0:
            self.send_error_json(HTTPStatus.LENGTH_REQUIRED, "上传需要 Content-Length")
            return
        if length > MAX_UPLOAD_SIZE:
            self.send_error_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "书籍超过服务器允许的大小")
            return
        ensure_storage()
        book_id = uuid.uuid4().hex[:16]
        stored_name = f"{book_id}{suffix}"
        target = BOOK_DIR / stored_name
        temp = BOOK_DIR / f".{stored_name}.part"
        digest = hashlib.sha256()
        remaining = length
        try:
            with temp.open("wb") as output:
                while remaining > 0:
                    chunk = self.rfile.read(min(STREAM_CHUNK_SIZE, remaining))
                    if not chunk:
                        raise OSError("上传连接提前中断")
                    output.write(chunk)
                    digest.update(chunk)
                    remaining -= len(chunk)
            temp.replace(target)
        except Exception as exc:
            temp.unlink(missing_ok=True)
            self.send_error_json(HTTPStatus.BAD_REQUEST, str(exc) or "上传失败")
            return
        stamp = now_iso()
        record = {
            "id": book_id,
            "name": name,
            "stored_name": stored_name,
            "size": length,
            "format": suffix.removeprefix("."),
            "content_type": self.headers.get("Content-Type") or mimetypes.guess_type(name)[0] or "application/octet-stream",
            "imported_at": stamp,
            "modified_at": stamp,
            "sha256": digest.hexdigest(),
        }
        records = load_books()
        records.append(record)
        save_books(records)
        threading.Thread(target=generate_cover, args=(record,), daemon=True).start()
        self.send_json({"book": public_book(record)}, HTTPStatus.CREATED)

    def update_progress(self, raw_book_id: str) -> None:
        book_id = clean_book_id(raw_book_id)
        if not book_id or find_book(book_id) is None:
            self.send_error_json(HTTPStatus.NOT_FOUND, "书籍不存在")
            return
        try:
            payload = self.read_small_json()
        except (ValueError, json.JSONDecodeError, UnicodeDecodeError) as exc:
            self.send_error_json(HTTPStatus.BAD_REQUEST, str(exc) or "阅读进度格式不正确")
            return
        progress = min(max(float(payload.get("progress", 0)), 0), 1)
        position = max(int(payload.get("position", 0)), 0)
        with metadata_lock:
            all_progress = read_json_file(PROGRESS_PATH, {})
            all_progress[book_id] = {
                "progress": progress,
                "position": position,
                "updated_at": now_iso(),
            }
            write_json_file(PROGRESS_PATH, all_progress)
        self.send_json({"ok": True})

    def send_book_cover(self, raw_book_id: str) -> None:
        record = find_book(raw_book_id)
        if record is None:
            self.send_error_json(HTTPStatus.NOT_FOUND, "书籍不存在")
            return
        cover = generate_cover(record)
        if cover is None or not cover.exists():
            self.send_error_json(HTTPStatus.NOT_FOUND, "这本书暂时没有封面")
            return
        size = cover.stat().st_size
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "image/jpeg")
        self.send_header("Content-Length", str(size))
        self.send_header("Cache-Control", "private, max-age=86400")
        self.send_header("ETag", f'"{record.get("id")}-{size}"')
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        with cover.open("rb") as file:
            shutil.copyfileobj(file, self.wfile, length=256 * 1024)

    def send_book_file(self, raw_book_id: str, send_body: bool) -> None:
        record = find_book(raw_book_id)
        if record is None:
            self.send_error_json(HTTPStatus.NOT_FOUND, "书籍不存在")
            return
        file_path = stored_path(record)
        if not file_path.exists() or not file_path.is_file():
            self.send_error_json(HTTPStatus.NOT_FOUND, "书籍文件缺失")
            return
        size = file_path.stat().st_size
        start, end = 0, max(0, size - 1)
        status = HTTPStatus.OK
        range_header = self.headers.get("Range", "").strip()
        if range_header:
            match = re.fullmatch(r"bytes=(\d*)-(\d*)", range_header)
            if not match or not any(match.groups()):
                self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                self.send_header("Content-Range", f"bytes */{size}")
                self.end_headers()
                return
            raw_start, raw_end = match.groups()
            if raw_start:
                start = int(raw_start)
                end = int(raw_end) if raw_end else max(0, size - 1)
            else:
                start = max(0, size - int(raw_end))
            if size == 0 or start >= size or end < start:
                self.send_response(HTTPStatus.REQUESTED_RANGE_NOT_SATISFIABLE)
                self.send_header("Content-Range", f"bytes */{size}")
                self.end_headers()
                return
            end = min(end, size - 1)
            status = HTTPStatus.PARTIAL_CONTENT
        length = max(0, end - start + 1) if size else 0
        name = str(record.get("name", file_path.name))
        content_type = str(record.get("content_type") or mimetypes.guess_type(name)[0] or "application/octet-stream")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Last-Modified", formatdate(file_path.stat().st_mtime, usegmt=True))
        self.send_header("Content-Disposition", f"attachment; filename*=UTF-8''{quote(name)}")
        self.send_header("Cache-Control", "private, no-transform")
        self.send_header("ETag", f'"{record.get("sha256", record.get("id"))}"')
        self.send_header("X-Content-Type-Options", "nosniff")
        if status == HTTPStatus.PARTIAL_CONTENT:
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.end_headers()
        if not send_body or length == 0:
            return
        remaining = length
        with file_path.open("rb") as file:
            file.seek(start)
            while remaining > 0:
                chunk = file.read(min(STREAM_CHUNK_SIZE, remaining))
                if not chunk:
                    break
                try:
                    self.wfile.write(chunk)
                except (BrokenPipeError, ConnectionResetError):
                    break
                remaining -= len(chunk)


def main() -> None:
    ensure_storage()
    server = ThreadingHTTPServer((HOST, PORT), InkShelfHandler)
    server.daemon_threads = True
    print(f"InkShelf private library listening on http://{HOST}:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
