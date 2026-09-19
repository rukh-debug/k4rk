#!/usr/bin/env python3
"""Exercise real QML text layout with an isolated home and no server account."""

import os
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parent.parent


class Server(BaseHTTPRequestHandler):
    requests = []

    def log_message(self, *_):
        pass

    def reply(self, value):
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(value).encode())

    def do_GET(self):
        if self.path in ('/api/v1/chats/slow', '/api/v1/chats/fast'):
            ident = self.path.rsplit('/', 1)[1]
            if ident == 'slow':
                time.sleep(0.3)
            self.reply({'id': ident, 'title': ident, 'chat': {'history': {
                'currentId': ident, 'messages': {ident: {'id': ident, 'role': 'user', 'content': ident, 'parentId': None}}}}})
        elif self.path.startswith('/api/v1/chats/'):
            self.reply([])
        else:
            self.reply({'data': [{'id': 'fixture-model'}]})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.requests.append((self.path, body))
        if self.path == '/api/chat/completions':
            self.send_response(200)
            self.send_header('Content-Type', 'text/event-stream')
            self.end_headers()
            try:
                if body['messages'][-1]['content'] == 'Slow':
                    time.sleep(0.4)
                for delta in ({'reasoning_content': 'Consider the question.'},
                              {'content': '# Answer\n\nA streamed reply.\n\n```python\nprint(42)\n```'}):
                    self.wfile.write(('data:' + json.dumps({'choices': [{'delta': delta}]}) + '\n\n').encode())
                    self.wfile.flush()
                    time.sleep(0.08)
                self.wfile.write(b'data: [DONE]\n\n')
            except (BrokenPipeError, ConnectionResetError):
                pass
        elif self.path == '/api/v1/tasks/title/completions':
            self.reply({'choices': [{'message': {'content': 'Fixture chat'}}]})
        else:
            if body.get('chat', {}).get('title') == 'Slow save':
                time.sleep(0.35)
            self.reply({'id': 'fixture-chat', 'chat': body.get('chat', {})})


def main():
    server = ThreadingHTTPServer(('127.0.0.1', 0), Server)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    with tempfile.TemporaryDirectory(prefix='k4-openwebui-ui-') as directory:
        root = Path(directory)
        # Exercise the real stdin clipboard path without changing the desktop clipboard.
        clipboard = root / 'wl-copy'
        clipboard.write_text(f'#!{sys.executable}\nimport pathlib, sys\npathlib.Path({str(root / "copied.txt")!r}).write_text(sys.stdin.read())\n')
        clipboard.chmod(0o755)
        (root / 'shell.qml').write_text((ROOT / 'tools/openwebui-test.qml').read_text())
        env = dict(os.environ, HOME=str(root), XDG_CACHE_HOME=str(root / 'cache'),
                   PATH=str(root) + os.pathsep + os.environ['PATH'],
                   XDG_DATA_HOME=str(root / 'data'), QT_QPA_PLATFORM='wayland',
                   QML_IMPORT_PATH=str(ROOT / 'api'),
                   K4_OPENWEBUI_TEST_URL=f'http://127.0.0.1:{server.server_port}',
                   K4_OPENWEBUI_TEST_SUITE=str(ROOT / 'tools/tst_openwebui.qml'))
        result = subprocess.run(['quickshell', '-p', str(root / 'shell.qml')], env=env,
                                capture_output=True, text=True, timeout=40)
        output = result.stdout + result.stderr
        print(output)
        errors = ('TypeError:', 'ReferenceError:', 'Unable to assign', 'Binding loop',
                  'Error loading configuration', 'is not a type', 'Cannot assign', 'FAIL!')
        if result.returncode or 'OpenWebUI UI:' not in output or any(error in output for error in errors):
            raise SystemExit(1)
        completions = [body for path, body in Server.requests if path == '/api/chat/completions']
        assert any('Selected text:\nAttached context' in message['content']
                   for body in completions for message in body['messages'] if isinstance(message['content'], str))
        assert all('chat_id' not in body for body in completions)
        assert (root / 'copied.txt').read_text() == 'large code block\n' * 12000
    server.shutdown()


if __name__ == '__main__':
    main()
