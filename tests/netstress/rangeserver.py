#!/usr/bin/env python3
"""Static file server with HTTP Range support (what a Jellyfin server does for direct play),
threaded, for streaming test clips to the board.  rangeserver.py <bind-ip> <port> <dir>"""
import http.server, os, re, sys, shutil


class Handler(http.server.SimpleHTTPRequestHandler):
    def send_head(self):
        path = self.translate_path(self.path)
        if os.path.isdir(path) or not os.path.isfile(path):
            return super().send_head()
        size = os.path.getsize(path)
        m = re.match(r"bytes=(\d*)-(\d*)$", self.headers.get("Range", ""))
        f = open(path, "rb")
        if not m:
            self.send_response(200)
            start, end = 0, size - 1
        else:
            a, b = m.groups()
            if a == "":                      # suffix range: last N bytes
                start, end = max(0, size - int(b)), size - 1
            else:
                start, end = int(a), min(int(b) if b else size - 1, size - 1)
            if start >= size or start > end:
                f.close()
                self.send_response(416)
                self.send_header("Content-Range", f"bytes */{size}")
                self.end_headers()
                return None
            self.send_response(206)
            self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
        self.send_header("Content-Type", self.guess_type(path))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Content-Length", str(end - start + 1))
        self.end_headers()
        f.seek(start)
        self._remaining = end - start + 1
        return f

    def copyfile(self, src, dst):
        n = getattr(self, "_remaining", None)
        if n is None:
            return shutil.copyfileobj(src, dst)
        while n > 0:
            buf = src.read(min(1 << 20, n))
            if not buf:
                break
            try:
                dst.write(buf)
            except (BrokenPipeError, ConnectionResetError):
                break
            n -= len(buf)


if __name__ == "__main__":
    ip, port, root = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    os.chdir(root)
    http.server.ThreadingHTTPServer((ip, port), Handler).serve_forever()
