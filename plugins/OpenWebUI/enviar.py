#!/usr/bin/env python3
#  One chat turn, posted to OpenWebUI with the answer streamed back
#  line by line — the same SSE the bar's line reader already parses.
#
#  Why a script and not curl from QML: a screenshot becomes a data
#  URL megabytes long, and the kernel caps a single argument at
#  128 KB — `curl -d <payload>` could simply never start, and the
#  turn died in silence. Here the payload travels as a file path
#  and the image is embedded inside, where size is not a law.
#
#      python3 enviar.py <url> <token> <payload.json> [image]
#
#  Errors — HTTP or network — are printed as ONE JSON error line,
#  shaped like an API error body, so the bar reads them through the
#  same parser as everything else and the chat shows them as the
#  turn's answer instead of nothing at all.

import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request


def fail(message):
    print(json.dumps({"error": {"message": message}}), flush=True)
    sys.exit(0)


def read_payload(path):
    #  The file is written a tick before this process runs; a brief
    #  retry also covers a half-written read.
    for _ in range(20):
        try:
            with open(path, "r") as f:
                return json.load(f)
        except (OSError, ValueError):
            time.sleep(0.1)
    fail("payload file never became readable: " + path)


def attach_image(payload, path):
    #  The last message is this turn's prompt; its text becomes the
    #  multimodal pair the model reads. Screenshots arrive as PNG.
    if not path or not os.path.isfile(path):
        return
    try:
        with open(path, "rb") as f:
            data = base64.b64encode(f.read()).decode("ascii")
    except OSError as e:
        fail("image unreadable: %s" % e)
    messages = payload.get("messages") or []
    if not messages:
        return
    messages[-1]["content"] = [
        {"type": "text", "text": str(messages[-1].get("content") or "")},
        {"type": "image_url",
         "image_url": {"url": "data:image/png;base64," + data}},
    ]


def main():
    if len(sys.argv) < 5:
        fail("enviar.py: expected url, token, payload file and image")
    url, token, payload_path, image_path = sys.argv[1:5]

    payload = read_payload(payload_path)
    attach_image(payload, image_path)

    request = urllib.request.Request(
        url.rstrip("/") + "/api/v1/chat/completions",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json",
                 "Authorization": "Bearer " + token},
        method="POST")
    try:
        response = urllib.request.urlopen(request, timeout=300)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:300]
        fail("HTTP %s: %s" % (e.code, detail))
    except Exception as e:                       # network, dns, tls
        fail(str(e))

    for raw in response:
        line = raw.decode("utf-8", "replace").strip()
        if line:
            print(line, flush=True)


if __name__ == "__main__":
    main()
