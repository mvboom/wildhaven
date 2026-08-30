#!/usr/bin/env python3
"""Serve a Godot Web export locally with what a threaded/large-payload export needs.

Two things plain `python3 -m http.server` doesn't give you, both of which matter for a
Godot Web export in particular:

1. COOP/COEP headers (Cross-Origin-Opener-Policy / Cross-Origin-Embedder-Policy). Without
   them a browser refuses SharedArrayBuffer, so a thread_support=true export silently
   fails to use threads. Harmless to send for a single-threaded export too.

2. HTTP Range support (206 Partial Content / Accept-Ranges). Godot's Web loader and
   browsers can fetch large assets (the .wasm and .pck here run 30-40MB) with Range
   requests, and any intermediary that forwards/proxies the connection (e.g. a devcontainer
   or Codespaces port-forward tunnel) may retry an interrupted transfer as a ranged
   request. `http.server.SimpleHTTPRequestHandler` doesn't implement Range at all — it
   always returns the full file with a plain 200, which a Range-aware client/proxy can
   misinterpret, and a connection that drops mid-transfer over an unreliable tunnel has no
   way to resume. That reads as "the payload got truncated and the game never loads." This
   handler answers Range requests correctly (206, Content-Range, Accept-Ranges: bytes) and
   serves HTTP/1.1 with keep-alive so a single dropped chunk doesn't tear down the whole
   transfer.

Usage:
    python3 scripts/serve-web-build.py <directory> [port]

Example:
    python3 scripts/serve-web-build.py /tmp/web_export_threaded 8070
"""

import http.server
import os
import re
import sys


class RangeCOOPHandler(http.server.SimpleHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate")
        self.send_header("Accept-Ranges", "bytes")
        super().end_headers()

    def do_GET(self):
        self._serve(send_body=True)

    def do_HEAD(self):
        self._serve(send_body=False)

    def _serve(self, send_body: bool) -> None:
        path = self.translate_path(self.path)

        if os.path.isdir(path):
            # Directory listing / index.html resolution: defer to the base class's own
            # logic rather than reimplementing it.
            if send_body:
                super().do_GET()
            else:
                super().do_HEAD()
            return

        if not os.path.exists(path):
            self.send_error(404, "File not found")
            return

        try:
            f = open(path, "rb")
        except OSError:
            self.send_error(404, "File not found")
            return

        try:
            file_len = os.fstat(f.fileno()).st_size
            ctype = self.guess_type(path)
            start, end, is_range = self._parse_range(file_len)

            if start is None:
                self.send_response(416)
                self.send_header("Content-Range", "bytes */%d" % file_len)
                self.end_headers()
                return

            length = end - start + 1
            self.send_response(206 if is_range else 200)
            self.send_header("Content-type", ctype)
            self.send_header("Content-Length", str(length))
            if is_range:
                self.send_header("Content-Range", "bytes %d-%d/%d" % (start, end, file_len))
            self.end_headers()

            if not send_body:
                return
            f.seek(start)
            remaining = length
            chunk_size = 64 * 1024
            while remaining > 0:
                chunk = f.read(min(chunk_size, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)
        finally:
            f.close()

    def _parse_range(self, file_len: int):
        """Returns (start, end, is_range). (None, None, False) means unsatisfiable."""
        range_header = self.headers.get("Range")
        if not range_header:
            return 0, file_len - 1, False

        match = re.match(r"bytes=(\d*)-(\d*)$", range_header.strip())
        if not match:
            return 0, file_len - 1, False

        start_str, end_str = match.groups()
        if start_str == "" and end_str == "":
            return 0, file_len - 1, False

        if start_str == "":
            # Suffix range: last N bytes.
            suffix_len = int(end_str)
            start = max(0, file_len - suffix_len)
            end = file_len - 1
        else:
            start = int(start_str)
            end = int(end_str) if end_str else file_len - 1

        if start >= file_len or start > end:
            return None, None, False
        end = min(end, file_len - 1)
        return start, end, True


def main() -> None:
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    directory = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 8070

    handler = lambda *args, **kwargs: RangeCOOPHandler(*args, directory=directory, **kwargs)
    http.server.test(HandlerClass=handler, port=port, bind="0.0.0.0")


if __name__ == "__main__":
    main()
