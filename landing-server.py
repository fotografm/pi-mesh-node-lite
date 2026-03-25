#!/usr/bin/env python3
"""
landing-server.py  —  raspi30
Serves landing.html and notes.html on port 80.
Handles:
  GET  /api/notes          -> JSON array of all notes
  POST /api/notes          -> create note, returns note JSON
  PUT  /api/notes/{id}     -> update note
  DELETE /api/notes/{id}   -> delete note
  GET  /notes              -> legacy single note text (for inline widget)
  POST /notes              -> legacy single note save
  POST /shutdown           -> system shutdown
"""

import asyncio
import json
import logging
import mimetypes
import signal
import subprocess
import time
import uuid
from pathlib import Path

LOG_LEVEL = logging.INFO
HTTP_HOST = "0.0.0.0"
HTTP_PORT = 80

HOME    = Path.home()
RASPI30 = HOME / "raspi30"

STATIC = {
    "/":             RASPI30 / "landing.html",
    "/landing.html": RASPI30 / "landing.html",
    "/notes.html":   RASPI30 / "notes.html",
    "/dseg7.woff2":  RASPI30 / "dseg7.woff2",
}

NOTES_JSON = RASPI30 / "notes.json"
NOTES_TXT  = RASPI30 / "notes.txt"
MIME_EXTRA = {".woff2": "font/woff2"}

logging.basicConfig(
    level=LOG_LEVEL,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("landing-server")


# ── Notes JSON storage helpers ────────────────────────────────────────────

def load_notes() -> list:
    if NOTES_JSON.exists():
        try:
            return json.loads(NOTES_JSON.read_text(encoding="utf-8"))
        except Exception:
            return []
    return []


def save_notes(notes: list):
    NOTES_JSON.write_text(json.dumps(notes, ensure_ascii=False, indent=2), encoding="utf-8")


def ok_json(writer, data):
    body = json.dumps(data, ensure_ascii=False).encode("utf-8")
    header = (
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: application/json; charset=utf-8\r\n"
        f"Content-Length: {len(body)}\r\n"
        "Connection: close\r\n"
        "\r\n"
    ).encode()
    writer.write(header + body)


def ok_text(writer, text: str):
    body = text.encode("utf-8")
    header = (
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: text/plain; charset=utf-8\r\n"
        f"Content-Length: {len(body)}\r\n"
        "Connection: close\r\n"
        "\r\n"
    ).encode()
    writer.write(header + body)


def not_found(writer):
    msg = b"Not found"
    writer.write(
        b"HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n"
        + f"Content-Length: {len(msg)}\r\nConnection: close\r\n\r\n".encode()
        + msg
    )


def get_body(request: str) -> str:
    idx = request.find("\r\n\r\n")
    return request[idx + 4:] if idx >= 0 else ""


# ── Request handler ───────────────────────────────────────────────────────

async def handle(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    try:
        request = (await reader.read(8192)).decode("utf-8", errors="replace")
        if not request:
            return
        first_line = request.split("\r\n")[0]
        parts = first_line.split()
        if len(parts) < 2:
            return
        method = parts[0]
        path   = parts[1].split("?")[0]

        # ── GET /api/notes ────────────────────────────────────────────────
        if method == "GET" and path == "/api/notes":
            ok_json(writer, load_notes())
            await writer.drain()
            return

        # ── POST /api/notes (create) ──────────────────────────────────────
        if method == "POST" and path == "/api/notes":
            notes = load_notes()
            now   = int(time.time() * 1000)
            note  = {
                "id":      str(uuid.uuid4())[:8],
                "text":    json.loads(get_body(request) or "{}").get("text", ""),
                "created": now,
                "updated": now,
            }
            notes.insert(0, note)
            save_notes(notes)
            ok_json(writer, note)
            await writer.drain()
            return

        # ── PUT /api/notes/{id} (update) ──────────────────────────────────
        if method == "PUT" and path.startswith("/api/notes/"):
            note_id = path[len("/api/notes/"):]
            notes   = load_notes()
            body    = json.loads(get_body(request) or "{}")
            for n in notes:
                if n["id"] == note_id:
                    n["text"]    = body.get("text", n["text"])
                    n["updated"] = int(time.time() * 1000)
                    break
            save_notes(notes)
            ok_text(writer, "OK")
            await writer.drain()
            return

        # ── DELETE /api/notes/{id} ────────────────────────────────────────
        if method == "DELETE" and path.startswith("/api/notes/"):
            note_id = path[len("/api/notes/"):]
            notes   = [n for n in load_notes() if n["id"] != note_id]
            save_notes(notes)
            ok_text(writer, "OK")
            await writer.drain()
            return

        # ── GET /notes (legacy inline widget) ─────────────────────────────
        if method == "GET" and path == "/notes":
            text = NOTES_TXT.read_text(encoding="utf-8") if NOTES_TXT.exists() else ""
            ok_text(writer, text)
            await writer.drain()
            return

        # ── POST /notes (legacy inline widget) ────────────────────────────
        if method == "POST" and path == "/notes":
            NOTES_TXT.write_text(get_body(request), encoding="utf-8")
            ok_text(writer, "OK")
            await writer.drain()
            return

        # ── POST /shutdown ────────────────────────────────────────────────
        if method == "POST" and path == "/shutdown":
            log.info("Shutdown requested")
            ok_text(writer, "OK")
            await writer.drain()
            writer.close()
            await asyncio.sleep(1)
            subprocess.Popen(["/usr/bin/sudo", "/usr/bin/systemctl", "start", "raspi30-shutdown.service"])
            return

        # ── Static files ──────────────────────────────────────────────────
        file_path = STATIC.get(path)
        if file_path and file_path.exists():
            body   = file_path.read_bytes()
            suffix = file_path.suffix.lower()
            mime   = MIME_EXTRA.get(suffix) or mimetypes.guess_type(str(file_path))[0] or "text/plain"
            header = (
                "HTTP/1.1 200 OK\r\n"
                f"Content-Type: {mime}\r\n"
                f"Content-Length: {len(body)}\r\n"
                "Cache-Control: no-cache\r\n"
                "Connection: close\r\n"
                "\r\n"
            ).encode()
            writer.write(header + body)
            log.debug("200 %s (%d bytes)", path, len(body))
        else:
            not_found(writer)
            log.debug("404 %s", path)

        await writer.drain()
    except Exception as e:
        log.debug("Request error: %s", e)
    finally:
        try:
            writer.close()
        except Exception:
            pass


async def main():
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGTERM, signal.SIGINT):
        loop.add_signal_handler(sig, loop.stop)

    server = await asyncio.start_server(handle, HTTP_HOST, HTTP_PORT)
    log.info("landing-server listening on http://0.0.0.0:%d", HTTP_PORT)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
