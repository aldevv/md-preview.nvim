#!/usr/bin/env python3
"""
md-preview-server.py — Neovim markdown preview server
Pure-stdlib WebSocket, markdown-it-py rendering via _renderer.

Usage: python3 md-preview-server.py <file> <port> <theme>
"""

import os
import sys

# Make _renderer importable (lives next to this script).
sys.path.insert(0, os.path.dirname(os.path.abspath(os.path.realpath(__file__))))

from _renderer import render_body, build_page  # noqa: E402

import base64  # noqa: E402
import hashlib  # noqa: E402
import json  # noqa: E402
import struct  # noqa: E402
import threading  # noqa: E402
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer  # noqa: E402
from urllib.parse import urlparse  # noqa: E402


# ── Args ───────────────────────────────────────────────────────────────────
if len(sys.argv) < 4:
    print("Usage: md-preview-server.py <file> <port> <theme>", file=sys.stderr)
    sys.exit(1)

WATCHED_FILE = os.path.abspath(sys.argv[1])
PORT = int(sys.argv[2])
THEME = sys.argv[3]  # "dark" or "light"


# ── Shared state ───────────────────────────────────────────────────────────
_lock = threading.Lock()
_state = {
    "file": WATCHED_FILE,
    "html_cache": "",
    "ws_clients": set(),  # set of raw sockets
    "render_version": 0,
}


def _do_render():
    with _lock:
        filepath = _state["file"]
    html_body = render_body(filepath)
    with _lock:
        _state["html_cache"] = html_body
        _state["render_version"] += 1
        version = _state["render_version"]
    return version


# ── WebSocket helpers ──────────────────────────────────────────────────────
WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def _ws_handshake(handler):
    key = handler.headers.get("Sec-WebSocket-Key", "")
    accept = base64.b64encode(
        hashlib.sha1((key + WS_MAGIC).encode()).digest()
    ).decode()
    handler.send_response(101, "Switching Protocols")
    handler.send_header("Upgrade", "websocket")
    handler.send_header("Connection", "Upgrade")
    handler.send_header("Sec-WebSocket-Accept", accept)
    handler.end_headers()


def _ws_encode(message: str) -> bytes:
    data = message.encode("utf-8")
    n = len(data)
    if n <= 125:
        return struct.pack("BB", 0x81, n) + data
    elif n <= 65535:
        return struct.pack("!BBH", 0x81, 126, n) + data
    else:
        return struct.pack("!BBQ", 0x81, 127, n) + data


def _ws_read_frame(sock) -> tuple:
    """Returns (opcode, payload). Returns (8, b'') on close/error."""
    try:
        header = _recv_exact(sock, 2)
        if not header:
            return 8, b""
        opcode = header[0] & 0x0F
        length = header[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", _recv_exact(sock, 2))[0]
        elif length == 127:
            length = struct.unpack("!Q", _recv_exact(sock, 8))[0]
        masked = (header[1] & 0x80) != 0
        mask = _recv_exact(sock, 4) if masked else b"\x00\x00\x00\x00"
        payload = bytearray(_recv_exact(sock, length))
        if masked:
            for i in range(len(payload)):
                payload[i] ^= mask[i % 4]
        return opcode, bytes(payload)
    except Exception:
        return 8, b""


def _recv_exact(sock, n: int) -> bytes:
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            return buf
        buf += chunk
    return buf


def _broadcast(msg: str):
    frame = _ws_encode(msg)
    with _lock:
        clients = set(_state["ws_clients"])
    dead = set()
    for sock in clients:
        try:
            sock.sendall(frame)
        except Exception:
            dead.add(sock)
    if dead:
        with _lock:
            _state["ws_clients"] -= dead


# ── HTTP handler ───────────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # silence default access log

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/ws":
            self._handle_ws()
        elif path == "/reload":
            with _lock:
                version = _state["render_version"]
            self._json({"version": version})
        else:
            with _lock:
                html_body = _state["html_cache"]
            page = build_page(html_body, THEME, ws_port=PORT)
            self._html(page)

    def do_POST(self):
        path = urlparse(self.path).path
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length) if length else b""
        try:
            data = json.loads(body) if body else {}
        except json.JSONDecodeError:
            data = {}

        if path == "/render":
            filepath = data.get("file", "")
            if filepath:
                with _lock:
                    _state["file"] = filepath
            version = _do_render()
            _broadcast(json.dumps({"type": "reload", "version": version}))
            self._json({"ok": True, "version": version})
        elif path == "/scroll":
            line = data.get("line", 0)  # 1-indexed source line from Neovim
            _broadcast(json.dumps({"type": "scroll", "line": line}))
            self._json({"ok": True, "line": line})
        else:
            self.send_response(404)
            self.end_headers()

    def _html(self, content: str):
        encoded = content.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _json(self, data: dict):
        encoded = json.dumps(data).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _handle_ws(self):
        _ws_handshake(self)
        sock = self.connection
        with _lock:
            _state["ws_clients"].add(sock)
        try:
            while True:
                opcode, _ = _ws_read_frame(sock)
                if opcode == 8:  # close
                    break
        finally:
            with _lock:
                _state["ws_clients"].discard(sock)


# ── stdin reader thread ────────────────────────────────────────────────────
def _stdin_reader():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue

        mtype = msg.get("type", "")
        if mtype == "quit":
            os._exit(0)
        elif mtype == "render":
            filepath = msg.get("file", "")
            if filepath:
                with _lock:
                    _state["file"] = filepath
            version = _do_render()
            _broadcast(json.dumps({"type": "reload", "version": version}))
        elif mtype == "scroll":
            line = msg.get("line", 0)  # 1-indexed source line from Neovim
            _broadcast(json.dumps({"type": "scroll", "line": line}))


# ── Main ───────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    # Initial render
    _do_render()

    # Start stdin reader
    t = threading.Thread(target=_stdin_reader, daemon=True)
    t.start()

    # Start HTTP server
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"[md-preview] Serving on http://localhost:{PORT}/", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
