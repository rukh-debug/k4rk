#!/usr/bin/env python3
"""Protocol and native markdown regressions; no account or network required."""

import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch

from markdown_render import render

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('sender', ROOT / 'plugins/OpenWebUI/enviar.py')
sender = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sender)
PALETTE = dict(ink='#ffffff', muted='#999999', surface='#222222', track='#444444',
               link='#70b7ff', keyword='#9dbfff', string='#a6cfb0', number='#d8bd91')


class MarkdownTests(unittest.TestCase):
    def test_document(self):
        source = '# Title\n\n**Bold**, *italic*, ~~removed~~ and [reference][ref].\n\n' \
                 '> Quote\n\n- [x] Done\n- [ ] Next\n  - Nested\n\n' \
                 '```python\ndef hello():\n    return "<safe>"\n```\n\n' \
                 '| Name | Value |\n| :--- | ---: |\n| A | 12 |\n\n[ref]: https://example.com\n'
        blocks = render(source, PALETTE)
        self.assertEqual([b['kind'] for b in blocks], ['text', 'code', 'table'])
        prose = blocks[0]['html']
        for marker in ('<h1', '<strong>', '<em>', '<del>', '<blockquote>', '☑', '☐', 'Nested', 'https://example.com'):
            self.assertIn(marker, prose)
        self.assertEqual(blocks[1]['text'], 'def hello():\n    return "<safe>"\n')
        self.assertIn('&lt;safe&gt;', blocks[1]['html'])
        self.assertIn('color:#9dbfff', blocks[1]['html'])
        self.assertIn('<th', blocks[2]['html'])

    def test_incomplete_and_unknown_code(self):
        blocks = render('Before\n\n~~~unknown-language\n  <tag>\n', PALETTE)
        self.assertEqual(blocks[-1]['kind'], 'code')
        self.assertEqual(blocks[-1]['text'], '  <tag>\n')
        self.assertIn('&lt;tag&gt;', blocks[-1]['html'])

    def test_markup_is_inert(self):
        markup = ''.join(b['html'] for b in render('<script>alert(1)</script>\n\n'
            '[bad](javascript:alert) ![remote](https://example.com/image.png)', PALETTE))
        self.assertNotIn('<script>', markup)
        self.assertNotIn('href="javascript:', markup)
        self.assertNotIn('<img', markup)
        self.assertIn('Image: remote', markup)


class ProtocolTests(unittest.TestCase):
    def test_sse_framing(self):
        stream = io.BytesIO(b': keepalive\r\nevent: message\r\ndata:{"choices":\r\n'
                            b'data: []}\r\n\r\ndata: [DONE]\r\n\r\n')
        self.assertEqual(list(sender.events(stream)), ['{"choices":\n[]}', '[DONE]'])

    def test_reasoning_and_json(self):
        for field in ('reasoning_content', 'reasoning', 'thinking'):
            result = sender.normalize({'choices': [{'delta': {field: 'Consider this', 'content': ''}}]})
            self.assertEqual(result['reasoning'], 'Consider this')
        result = sender.normalize({'choices': [{'message': {'content': 'Answer', 'reasoning_content': 'Thought'},
                                               'finish_reason': 'stop'}]})
        self.assertEqual((result['type'], result['content'], result['finish']), ('message', 'Answer', 'stop'))
        self.assertEqual(sender.normalize({'error': 'Provider failed'})['message'], 'Provider failed')

    def test_request_and_stream(self):
        class Response(io.BytesIO):
            headers = {'Content-Type': 'text/event-stream'}
        response = Response('data:{"choices":[{"delta":{"content":"Hello 🌍"}}]}\n\ndata: [DONE]\n\n'.encode())
        output = io.StringIO()
        with patch.object(sender.urllib.request, 'urlopen', return_value=response) as request, patch('sys.stdout', output):
            sender.run({'url': 'https://example.com/root/', 'token': 'test-only',
                        'payload': {'model': 'example', 'messages': [], 'stream': True}})
        self.assertEqual(request.call_args.args[0].full_url, 'https://example.com/root/api/chat/completions')
        self.assertEqual(request.call_args.args[0].get_header('Authorization'), 'Bearer test-only')
        events = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(events[0]['content'], 'Hello 🌍')
        self.assertEqual(events[-1]['type'], 'done')

    def test_forced_non_streaming_response(self):
        class Response(io.BytesIO):
            headers = {'Content-Type': 'application/json'}
        response = Response(b'{"choices":[{"message":{"content":"Full answer"}}]}')
        output = io.StringIO()
        with patch.object(sender.urllib.request, 'urlopen', return_value=response), patch('sys.stdout', output):
            sender.run({'url': 'https://example.com', 'token': 'test', 'payload': {}})
        self.assertEqual(json.loads(output.getvalue().splitlines()[0])['type'], 'message')

    def test_truncated_stream_retains_partial_and_reports_error(self):
        class Response(io.BytesIO):
            headers = {'Content-Type': 'text/event-stream'}
        response = Response(b'data: {"choices":[{"delta":{"content":"Partial"}}]}\n\n')
        output = io.StringIO()
        with patch.object(sender.urllib.request, 'urlopen', return_value=response), patch('sys.stdout', output):
            sender.run({'url': 'https://example.com', 'token': 'test', 'payload': {}})
        events = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(events[0]['content'], 'Partial')
        self.assertEqual(events[1]['type'], 'error')


if __name__ == '__main__':
    unittest.main()
