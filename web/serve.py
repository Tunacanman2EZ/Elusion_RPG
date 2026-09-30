"""Serve the browser build the way the real site does, for testing at home.

    python web/serve.py                      # then open http://localhost:8060
    python web/serve.py --api http://127.0.0.1:5000 --port 8060 --dir builds/web

It does the two things a plain file server cannot, and both are why the game
would not run from one:

- ONE ADDRESS. The page and /api/ come from the same origin, as they will
  behind Caddy. The API sends no cross-site headers, so a page on :8060 calling
  :5000 directly would be refused by the browser. Here /api/ is passed through
  to the API.
- REFRESH MEANS UPDATE. Every file goes out with Cache-Control: no-cache, so
  the browser asks each load whether it has the newest copy (a cheap 304 when
  it does) and a new export is picked up by a refresh, not by clearing a cache.

Standard library only. Not for the internet: no TLS, no limits. The site runs
behind Caddy - see DEPLOY.md in the API repository.
"""
import argparse
import http.server
import os
import sys
import urllib.error
import urllib.request

# Windows reads MIME types from the registry, which often has no .wasm, and a
# browser refuses to stream-compile a .wasm served as anything else.
TYPES = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".png": "image/png",
    ".ico": "image/x-icon",
    ".json": "application/json",
}

# Not passed through in either direction: they describe one connection, not
# the request or the answer.
HOP_BY_HOP = {"connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
              "te", "trailers", "transfer-encoding", "upgrade", "host", "content-length"}


def make_handler(root, api, threads):
    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=root, **kwargs)

        def guess_type(self, path):
            return TYPES.get(os.path.splitext(path)[1].lower()) or super().guess_type(path)

        def end_headers(self):
            if not self.path.startswith("/api/"):
                self.send_header("Cache-Control", "no-cache")
                if threads:
                    # Only a build exported with thread support needs these,
                    # and they stop the page embedding anything cross-site.
                    self.send_header("Cross-Origin-Opener-Policy", "same-origin")
                    self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
            super().end_headers()

        def _proxy(self):
            length = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(length) if length else None
            request = urllib.request.Request(api + self.path, data=body, method=self.command)
            for name, value in self.headers.items():
                if name.lower() not in HOP_BY_HOP:
                    request.add_header(name, value)
            try:
                with urllib.request.urlopen(request, timeout=60) as answer:
                    self._relay(answer.status, answer.headers, answer.read())
            except urllib.error.HTTPError as refused:
                self._relay(refused.code, refused.headers, refused.read())
            except (urllib.error.URLError, OSError) as down:
                message = ('{"error": "Bad Gateway", "message": "The API at %s did not answer: %s"}'
                           % (api, str(down).replace('"', "'"))).encode()
                self._relay(502, {"Content-Type": "application/json"}, message)

        def _relay(self, status, headers, body):
            self.send_response(status)
            for name, value in headers.items():
                if name.lower() not in HOP_BY_HOP:
                    self.send_header(name, value)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path.startswith("/api/"):
                return self._proxy()
            return super().do_GET()

        def do_HEAD(self):
            if self.path.startswith("/api/"):
                return self._proxy()
            return super().do_HEAD()

        def do_POST(self):
            return self._proxy() if self.path.startswith("/api/") else self.send_error(405)

        def do_PUT(self):
            return self._proxy() if self.path.startswith("/api/") else self.send_error(405)

        def do_DELETE(self):
            return self._proxy() if self.path.startswith("/api/") else self.send_error(405)

    return Handler


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    project = os.path.dirname(here)
    parser = argparse.ArgumentParser(description="Serve the browser build with /api/ passed through.")
    parser.add_argument("--dir", default=os.path.join(project, "builds", "web"),
                        help="the export folder (default: builds/web)")
    parser.add_argument("--port", type=int, default=8060)
    parser.add_argument("--api", default="http://127.0.0.1:5000", help="where the API is running")
    parser.add_argument("--threads", action="store_true",
                        help="send the isolation headers a thread-support export needs")
    args = parser.parse_args()

    root = os.path.abspath(args.dir)
    if not os.path.isfile(os.path.join(root, "index.html")):
        sys.exit("No index.html in %s. Export the Web preset first (Project > Export > Web)." % root)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port),
                                             make_handler(root, args.api.rstrip("/"), args.threads))
    print("Serving %s at http://localhost:%d  (/api/ -> %s)" % (root, args.port, args.api))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
