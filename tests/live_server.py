#!/usr/bin/env python3
"""A stand-in for the backend bird talks to, for the live end-to-end run.

The port is exercised over real TCP with real curl, so what is being tested is the
transport the program actually uses rather than a description of it: the argv
curl gets, the headers, the status, the body, and the error each status maps to.

Every request is appended to the log named on the command line, so the shapes bird
sends can be checked against the shapes X and Sweetistics expect, rather than
inferred from bird's own output.

    python3 tests/live_server.py 8931 /tmp/live_requests.log /tmp/live_port

Port 0 asks the operating system for a free one, which is what the test does: a
fixed port can be taken by a server left over from an earlier run, and then the
requests are served, the log goes somewhere else, and every case passes against
the wrong process. The port actually bound is written to the third argument so
the caller can read it.

Routes are the operation ids bird is pointed at with `--op-*`, plus the media
service and the mentions timeline, which are pointed at with `--media-upload-base`
and `--mentions-url`:

    POST /viewer                    200  a viewer payload, the shape `whoami` reads
    POST /detail                    404  X's own not-found body
    POST /search                    429  a rate-limit body with no JSON at all
    POST /tweet                     500  an upstream failure
    POST /html                      200  HTML rather than JSON, which is what a wrong route gives
    POST /media/upload.json         200  a media id, the shape an upload returns
    POST /media/metadata/create.json 200 an empty acceptance of an alt text
    POST /graphql/create-tweet/CreateTweet 200  a created tweet
    GET  /mentions.json             200  a mentions timeline

A GET is logged too, with an empty body: `mentions` is the one read that is not a
POST, and "no request body" is exactly what makes it different.
"""

import json
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

LOG = sys.argv[2]
PORT = int(sys.argv[1])
PORTOUT = sys.argv[3] if len(sys.argv) > 3 else None

# About 300 KB, in the shape a real answer has. The size is the point: a 138 KB
# tweet once took the program down with a stack overflow, because splitting the
# status off the end of it walked one character per stack frame. A route that
# answers with something this big is what keeps that from coming back.
def big_body() -> str:
    entry = {"content": {"itemContent": {"tweet_results": {"result": {"legacy": {
        "full_text": "padding, so the body is the size a real thread is and not an id",
        "id_str": "900001"}}}}}}
    entries = [entry for _ in range(1200)]
    payload = {"data": {"threaded_conversation_with_injections_v2": {
        "instructions": [{"entries": entries}]}}}
    return json.dumps(payload)


BODIES = {
    "/viewer": (200, "application/json",
                '{"data":{"viewer":{"user_results":{"result":{"rest_id":"1","legacy":'
                '{"screen_name":"bird_live_probe","name":"Bird Probe"}}}}}}'),
    "/big": (200, "application/json", big_body()),
    "/detail": (404, "application/json", '{"errors":[{"message":"No tweet found"}]}'),
    "/search": (429, "text/plain", "Rate limit exceeded"),
    "/tweet": (500, "application/json", '{"errors":[{"message":"Internal error"}]}'),
    "/html": (200, "text/html", "<!doctype html><html><body>not the api</body></html>"),
    # The media service, as an upload returns it. The id is the whole answer the
    # fold needs: everything after the upload is addressed by it.
    "/media/upload.json": (200, "application/json",
                           '{"media_id":111,"media_id_string":"111"}'),
    "/media/metadata/create.json": (200, "application/json", "{}"),
    # The post, at the graphql base and operation id the run names.
    "/graphql/create-tweet/CreateTweet": (200, "application/json",
                                    '{"data":{"create_tweet":{"tweet_results":{"result":'
                                    '{"rest_id":"5150","legacy":{"full_text":"media live"}}}}}}'),
    # The mentions timeline: a REST read, so it is a GET with the count in the
    # query string rather than a variable in a body.
    "/mentions.json": (200, "application/json",
                       '{"globalObjects":{"tweets":{"11":{"full_text":"@bird hello"}}},'
                       '"timeline":{"instructions":[]}}'),
}


def route_of(path: str) -> str:
    """The routes above are paths; a query string is a variable, not a route."""
    return path.split("?", 1)[0]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length).decode("utf-8", "replace")
        self.record(body, length)
        status, ctype, text = BODIES.get(route_of(self.path), (404, "application/json",
                                                              '{"errors":[{"message":"no such route"}]}'))
        self.answer(status, ctype, text)

    def do_GET(self):
        self.record("", 0)
        status, ctype, text = BODIES.get(route_of(self.path), (404, "application/json",
                                                              '{"errors":[{"message":"no such route"}]}'))
        self.answer(status, ctype, text)

    def record(self, body: str, length: int):
        with open(LOG, "a") as f:
            f.write(json.dumps({
                "method": self.command,
                "path": self.path,
                "content_type": self.headers.get("content-type"),
                "authorization": self.headers.get("authorization"),
                # The session cookie and the csrf token are logged because which
                # credential a run picked is only observable on the wire: the
                # envelope says "environment" whichever name supplied it.
                "cookie": self.headers.get("cookie"),
                "csrf": self.headers.get("x-csrf-token"),
                "accept": self.headers.get("accept"),
                "body": body,
                "body_len": length,
            }) + "\n")

    def answer(self, status: int, ctype: str, text: str):
        payload = text.encode()
        self.send_response(status)
        self.send_header("content-type", ctype)
        self.send_header("content-length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    if PORTOUT:
        with open(PORTOUT, "w") as f:
            f.write(str(server.server_address[1]))
    server.serve_forever()
