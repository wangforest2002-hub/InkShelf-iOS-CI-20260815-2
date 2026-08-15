from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse


MAX_INPUT_BYTES = 50_000_000
PROCESS_LOCK = threading.Lock()


class SharpBridge:
    def __init__(self, entry: Path, timeout: int) -> None:
        self.entry = entry.resolve(strict=True)
        self.timeout = timeout

    def process(self, data: bytes, suffix: str) -> bytes:
        with PROCESS_LOCK:
            root = Path(tempfile.mkdtemp(prefix="inkshelf-sharp-"))
            try:
                source = root / f"input{suffix}"
                output = root / "output"
                source.write_bytes(data)
                output.mkdir()
                command = [
                    "powershell.exe",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    str(self.entry),
                    str(source),
                    "-OutputDir",
                    str(output),
                    "-Scale",
                    "2",
                    "-Format",
                    "png",
                    "-Overwrite",
                ]
                finished = subprocess.run(
                    command,
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=self.timeout,
                    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                )
                candidates = sorted(output.glob("*_2x_sharp.png"))
                if finished.returncode != 0 or len(candidates) != 1:
                    detail = (finished.stderr or finished.stdout or "Sharp pipeline failed").strip()
                    raise RuntimeError(detail[-1200:])
                result = candidates[0].read_bytes()
                if not result.startswith(b"\x89PNG\r\n\x1a\n"):
                    raise RuntimeError("Sharp pipeline returned a non-PNG file")
                return result
            finally:
                shutil.rmtree(root, ignore_errors=True)


class Handler(BaseHTTPRequestHandler):
    bridge: SharpBridge
    server_version = "InkShelfSharpBridge/1.0"

    def do_GET(self) -> None:  # noqa: N802
        if urlparse(self.path).path != "/health":
            self.send_json(404, {"message": "not found"})
            return
        self.send_json(
            200,
            {
                "status": "ready",
                "profile": "sharp",
                "model": "realesrgan-x4plus-anime",
                "upscale": 4,
                "final_scale": 2,
                "downsample": "Lanczos",
                "format": "png",
            },
        )

    def do_POST(self) -> None:  # noqa: N802
        if urlparse(self.path).path != "/enhance":
            self.send_json(404, {"message": "not found"})
            return
        if self.headers.get("X-InkShelf-Profile", "").lower() != "sharp":
            self.send_json(400, {"message": "only the Sharp profile is allowed"})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_INPUT_BYTES:
            self.send_json(413, {"message": "input must be between 1 byte and 50 MB"})
            return
        data = self.rfile.read(length)
        content_type = self.headers.get("Content-Type", "").split(";", 1)[0].lower()
        suffix = {
            "image/jpeg": ".jpg",
            "image/png": ".png",
            "image/webp": ".webp",
        }.get(content_type)
        if not suffix:
            self.send_json(415, {"message": "supported formats: JPEG, PNG, WebP"})
            return
        try:
            result = self.bridge.process(data, suffix)
        except subprocess.TimeoutExpired:
            self.send_json(504, {"message": "Sharp processing timed out"})
            return
        except Exception as error:  # noqa: BLE001
            self.send_json(500, {"message": f"Sharp processing failed: {error}"})
            return
        self.send_response(200)
        self.send_header("Content-Type", "image/png")
        self.send_header("Content-Length", str(len(result)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-InkShelf-Model", "realesrgan-x4plus-anime")
        self.send_header("X-InkShelf-Profile", "sharp")
        self.send_header("X-InkShelf-Final-Scale", "2")
        self.end_headers()
        self.wfile.write(result)

    def send_json(self, status: int, value: dict) -> None:
        data = json.dumps(value, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, fmt: str, *args: object) -> None:
        print(f"{self.address_string()} - {fmt % args}", flush=True)


def main() -> int:
    parser = argparse.ArgumentParser(description="二次元小家 Sharp 图片清晰化电脑桥")
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--entry", required=True, type=Path)
    args = parser.parse_args()
    Handler.bridge = SharpBridge(args.entry, args.timeout)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print("二次元小家 Sharp 图片桥已启动", flush=True)
    print(f"监听地址：http://{args.host}:{args.port}", flush=True)
    print("固定方案：realesrgan-x4plus-anime 4x → Lanczos 2x → PNG", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nSharp 图片桥已停止。", flush=True)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
