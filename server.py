from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ASSETS = {"/": "index.html", "/index.html": "index.html", "/style.css": "style.css", "/calc.js": "calc.js", "/app.js": "app.js"}

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def _allowed(self):
        host = self.headers.get("Host", "")
        origin = self.headers.get("Origin")
        return host in {"127.0.0.1:8341", "localhost:8341"} and (origin is None or origin in {"http://127.0.0.1:8341", "http://localhost:8341"})

    def do_GET(self):
        self._serve_asset()

    def do_HEAD(self):
        self._serve_asset(head=True)

    def _serve_asset(self, head=False):
        asset = ASSETS.get(self.path.split("?", 1)[0])
        if not self._allowed():
            self.send_error(403, "Host or Origin is not allowed")
            return
        if asset is None:
            self.send_error(404, "Asset not found")
            return
        self.path = "/" + asset
        self.send_response(200)
        self.send_header("Content-Type", self.guess_type(asset))
        self.send_header("Content-Length", str((ROOT / asset).stat().st_size))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy", "default-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; img-src 'self' data:")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        if not head:
            self.wfile.write((ROOT / asset).read_bytes())

    def log_message(self, fmt, *args):
        pass

if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", 8341), Handler).serve_forever()
