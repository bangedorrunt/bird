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
    POST /bookmarks                 200  a bookmark timeline, the shape `bookmarks` reads
    POST /detail                    404  X's own not-found body
    POST /search                    429  a rate-limit body with no JSON at all
    POST /tweet                     500  an upstream failure
    POST /html                      200  HTML rather than JSON, which is what a wrong route gives
    POST /media/upload.json         200  a media id, the shape an upload returns
    POST /media/metadata/create.json 200 an empty acceptance of an alt text
    POST /graphql/create-tweet/CreateTweet 200  a created tweet
    POST /graphql/detail/TweetDetail 200  an article-shaped tweet, body and all
    GET  /mentions.json             200  a mentions timeline
    GET  /home                       200  the web client's own page, naming its bundle
    GET  /client-web/main.<hash>.js  200  a bundle carrying a bearer and four ops

A GET is logged too, with an empty body: `mentions` is the one read that is not a
POST, and "no request body" is exactly what makes it different.

The last two routes serve `bird login`: the page names the bundle, and the bundle
carries the bearer and the operation ids. Both are read out of what X serves in the
same shapes, so the flow runs over a real socket instead of against a recorded
document. The page is built per request because it has to name the port this
server actually bound, which is only known once it has one.
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
    # `rest_id` is what makes this a tweet rather than bytes: without it the fold
    # has nothing to collect and a 300 KB body would exercise the walk not at all.
    entry = {"content": {"itemContent": {"tweet_results": {"result": {
        "rest_id": "900001", "legacy": {
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
    # The bookmarks timeline, under its own key. The fold walks for tweets
    # wherever they are, so the key itself is the only thing this shape adds.
    "/bookmarks": (200, "application/json",
                  '{"data":{"bookmark_timeline_v2":{"timeline":{"instructions":[{"entries":[{"content":'
                  '{"itemContent":{"tweet_results":{"result":{"rest_id":"6060",'
                  '"legacy":{"full_text":"a saved tweet","id_str":"6060"}}}}}}]}]}}}}'),
    # The same timeline when it does NOT fit one page: two tweets and a bottom
    # cursor, then the page that cursor names. It has a route of its own because
    # `/bookmarks` is the one-page case a caller sees when X has nothing more to
    # send, and a stateful answer there would hide that.
    "/bookmarks-paged": (200, "application/json", "a paged timeline is built per request"),
    "/detail": (404, "application/json", '{"errors":[{"message":"No tweet found"}]}'),
    "/search": (429, "text/plain", "Rate limit exceeded"),
    "/tweet": (500, "application/json", '{"errors":[{"message":"Internal error"}]}'),
    "/html": (200, "text/html", "<!doctype html><html><body>not the api</body></html>"),
    # The media service, as an upload returns it. The id is the whole answer the
    # fold needs: everything after the upload is addressed by it.
    "/media/upload.json": (200, "application/json",
                           '{"media_id":111,"media_id_string":"111"}'),
    "/media/metadata/create.json": (200, "application/json", "{}"),
    # A post that is an X Article, at the graphql base and operation id the run
    # names. `legacy.full_text` is the t.co stub a client shows and the body is
    # under `article`; both are here because the fold's job is to answer with the
    # second, and a fixture carrying only the body would pass without the stub ever
    # being weighed against it.
    "/graphql/detail/TweetDetail": (200, "application/json",
                                    '{"data":{"threaded_conversation_with_injections_v2":{"instructions":'
                                    '[{"entries":[{"content":{"itemContent":{"tweet_results":{"result":'
                                    '{"rest_id":"12345","legacy":{"full_text":"https://t.co/stub","id_str":"12345",'
                                    '"lang":"zxx"},"article":{"article_results":{"result":{'
                                    '"title":"a live article","content_state":{"blocks":['
                                    '{"type":"header-one","text":"the head"},'
                                    '{"type":"unstyled","text":"the body"}]}}}}}}}}}]}]}}}'),
    # The post, at the graphql base and operation id the run names.
    "/graphql/create-tweet/CreateTweet": (200, "application/json",
                                    '{"data":{"create_tweet":{"tweet_results":{"result":'
                                    '{"rest_id":"5150","legacy":{"full_text":"media live"}}}}}}'),
    # The mentions timeline: a REST read, so it is a GET with the count in the
    # query string rather than a variable in a body. The tweet keeps its fields at
    # the top level, and its author is NOT in it: the author is a separate entry in
    # `globalObjects.users`, keyed by the tweet's `user_id_str`. That lookup beside
    # the tweet is the one thing this shape needs that the GraphQL one does not, so
    # the stand-in has to carry it or the case proves nothing about it.
    "/mentions.json": (200, "application/json",
                       '{"globalObjects":{"tweets":{"11":{"id_str":"11",'
                       '"full_text":"@bird hello","user_id_str":"55",'
                       '"created_at":"Sat Oct 11 00:00:00 +0000 2026"}},'
                       '"users":{"55":{"id_str":"55","screen_name":"bird_mentions_probe",'
                       '"name":"Bird Mentions Probe"}}},'
                       '"timeline":{"instructions":[]}}'),
}


# The two pages the paged route answers with, in order: page one carries the cursor
# whose token page two is asked for, and page two has no cursor because that is the
# end of the timeline.
def paged_page(n: int) -> str:
    if n == 0:
        return ('{"data":{"data":{"bookmark_timeline_v2":{"timeline":{"instructions":[{"entries":['
                '{"entryId":"tweet-6061","content":{"itemContent":{"tweet_results":{"result":'
                '{"rest_id":"6061","legacy":{"full_text":"the first saved","id_str":"6061"}}}}}},'
                '{"entryId":"tweet-6062","content":{"itemContent":{"tweet_results":{"result":'
                '{"rest_id":"6062","legacy":{"full_text":"the second saved","id_str":"6062"}}}}}},'
                '{"entryId":"cursor-bottom-1","content":{"entryType":"TimelineTimelineCursor",'
                '"cursorType":"Bottom","value":"LIVECURSOR1"}}]}]}}}}}')
    return ('{"data":{"data":{"bookmark_timeline_v2":{"timeline":{"instructions":[{"entries":['
            '{"entryId":"tweet-6063","content":{"itemContent":{"tweet_results":{"result":'
            '{"rest_id":"6063","legacy":{"full_text":"the third saved","id_str":"6063"}}}}}}]}]}}}}}')


# How many times each route has been asked, so the paged one can answer the second
# request with the page the cursor names. Process-wide and per route: one case in
# `tests/e2e.sh` reads two pages, and nothing else reads this route at all.
PAGED_SEEN = {}


def paged_route_n(route: str) -> int:
    n = PAGED_SEEN.get(route, 0)
    PAGED_SEEN[route] = n + 1
    return n


BUNDLE_PATH = "/client-web/main.livetest.js"

# The 20 leading `A`s are not decoration: the real bearer begins with them, and
# the reader searches for that head before the token, so a fixture without it
# would pass here and fail against X.
BUNDLE_JS = ("e.exports={queryId:\"LIVEVIEWERID1\",operationName:\"Viewer\",operationType:\"query\"}"
             ",{queryId:\"LIVEDETAILID2\",operationName:\"TweetDetail\",operationType:\"query\"}"
             ",{queryId:\"LIVESEARCHID3\",operationName:\"SearchTimeline\",operationType:\"query\"}"
             ",{queryId:\"LIVEBOOKMARKS5\",operationName:\"Bookmarks\",operationType:\"query\"}"
             ",{queryId:\"LIVECREATEID4\",operationName:\"CreateTweet\",operationType:\"mutation\"}"
             ",Bearer AAAAAAAAAAAAAAAAAAAA_LIVE_BEARER_TAIL\",")


def home_page(port: int) -> str:
    return ("<!doctype html><html><head>"
            f'<script defer src="http://127.0.0.1:{port}{BUNDLE_PATH}" nonce="x"></script>'
            "</head><body>a signed-in page</body></html>")


def route_of(path: str) -> str:
    """The routes above are paths; a query string is a variable, not a route."""
    return path.split("?", 1)[0]


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_POST(self):
        length = int(self.headers.get("content-length") or 0)
        body = self.rfile.read(length).decode("utf-8", "replace")
        self.record(body, length)
        route = route_of(self.path)
        if route == "/bookmarks-paged":
            self.answer(200, "application/json", paged_page(paged_route_n(route)))
        else:
            status, ctype, text = BODIES.get(route, (404, "application/json",
                                                     '{"errors":[{"message":"no such route"}]}'))
            self.answer(status, ctype, text)

    def do_GET(self):
        self.record("", 0)
        route = route_of(self.path)
        if route == "/home":
            self.answer(200, "text/html", home_page(self.server.server_address[1]))
        elif route == BUNDLE_PATH:
            self.answer(200, "application/javascript", BUNDLE_JS)
        else:
            status, ctype, text = BODIES.get(route, (404, "application/json",
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
