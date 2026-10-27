#!/usr/bin/env python3
import argparse
import functools
import http.server
import os


DEFAULT_ROOT = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "AirDesk", "Resources", "DesktopShell")
)


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "cross-origin")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args))


def main():
    parser = argparse.ArgumentParser(description="Serve the AirDesk desktop shell on loopback.")
    parser.add_argument("--root", default=DEFAULT_ROOT)
    parser.add_argument("--port", type=int, default=8123)
    args = parser.parse_args()

    root = os.path.abspath(args.root)
    handler = functools.partial(Handler, directory=root)
    server = http.server.ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    print("Serving %s at http://127.0.0.1:%d/" % (root, args.port))
    server.serve_forever()


if __name__ == "__main__":
    main()
