#!/usr/bin/env python3
"""Render CommonMark/GFM into native Qt text blocks over a JSON-lines pipe."""

import html
import json
import sys
from functools import lru_cache
from urllib.parse import urlsplit

import mistune
from mistune.plugins.table import table
from mistune.plugins.task_lists import task_lists
from mistune.plugins.formatting import strikethrough
from mistune.plugins.url import url
from pygments import lex
from pygments.lexers import get_lexer_by_name
from pygments.token import Token
from pygments.util import ClassNotFound


def safe_url(url):
    return url if urlsplit(url).scheme.lower() in ("https", "http", "mailto") else ""


class QtRenderer(mistune.HTMLRenderer):
    def __init__(self, palette):
        super().__init__(escape=True)
        self.palette = palette
        self.blocks = []

    def paragraph(self, text):
        return '<p style="margin-top:4px;margin-bottom:10px;line-height:135%;">' + text + '</p>'

    def heading(self, text, level, **attrs):
        size = (23, 20, 17, 15, 14, 14)[level - 1]
        return f'<h{level} style="font-size:{size}px;margin-top:14px;margin-bottom:8px;">{text}</h{level}>'

    def codespan(self, text):
        return '<span style="font-family:monospace;background-color:' + self.palette['surface'] + ';">' + html.escape(text) + '</span>'

    def link(self, text, url, title=None):
        target = safe_url(url)
        if not target:
            return text
        return '<a style="color:' + self.palette['link'] + ';" href="' + html.escape(target, quote=True) + '">' + text + '</a>'

    def image(self, text, url, title=None):
        # Remote images remain explicit links; the renderer never fetches assets.
        return self.link('Image: ' + (text or 'open image'), url, title)

    def block_code(self, code, info=None):
        language = (info or '').strip().split(' ', 1)[0]
        return '<pre>' + highlight(code, language, self.palette) + '</pre>'


def task_item(renderer, text, checked=False):
    return '<li>' + ('☑ ' if checked else '☐ ') + text + '</li>'


@lru_cache(maxsize=64)
def lexer_for(language):
    try:
        return get_lexer_by_name(language, stripnl=False, ensurenl=False)
    except ClassNotFound:
        return None


def highlight(code, language, palette):
    lexer = lexer_for(language) if language else None
    if lexer is None:
        return html.escape(code)
    spans = []
    for token, value in lex(code, lexer):
        color = (palette['muted'] if token in Token.Comment else
                 palette['string'] if token in Token.Literal.String else
                 palette['number'] if token in Token.Literal.Number else
                 palette['keyword'] if token in Token.Keyword else
                 palette['ink'])
        spans.append('<span style="color:' + color + ';">' + html.escape(value) + '</span>')
    return ''.join(spans)


def render(text, palette):
    renderer = QtRenderer(palette)
    parser = mistune.Markdown(renderer=renderer, plugins=[table, task_lists, strikethrough, url])
    renderer.register('task_list_item', task_item)
    # Parse the entire document to resolve references and nested structures. Only
    # top-level code and tables become separate interactive native blocks.
    state = parser.block.state_cls()
    normalized = text.replace('\r\n', '\n').replace('\r', '\n')
    state.process(normalized if normalized.endswith('\n') else normalized + '\n')
    parser.block.parse(state)
    for hook in parser.before_render_hooks:
        hook(parser, state)
    tokens = list(parser._iter_render(state.tokens, state))
    blocks, prose = [], []

    def flush():
        if prose:
            markup = renderer.render_tokens(prose, state).strip()
            if markup:
                blocks.append({'kind': 'text', 'html': markup, 'text': '', 'language': ''})
            prose.clear()

    for token in tokens:
        kind = token['type']
        if kind == 'block_code':
            flush()
            code = token.get('raw', '')
            language = token.get('attrs', {}).get('info', '').strip().split(' ', 1)[0]
            blocks.append({'kind': 'code', 'text': code, 'language': language,
                           'html': '<pre style="margin:0;">' + highlight(code, language, palette) + '</pre>'})
        elif kind == 'table':
            flush()
            markup = renderer.render_token(token, state).replace('<table>', '<table border="1" cellspacing="0" cellpadding="8" style="border-color:' + palette['track'] + ';">')
            markup = markup.replace('<th', '<th bgcolor="' + palette['surface'] + '"')
            blocks.append({'kind': 'table', 'html': markup, 'text': '', 'language': ''})
        else:
            prose.append(token)
    flush()
    return blocks


def main():
    for line in sys.stdin:
        request = {}
        try:
            request = json.loads(line)
            result = render(request['text'], request['palette'])
            print(json.dumps({'id': request['id'], 'revision': request['revision'], 'blocks': result}), flush=True)
        except Exception as error:
            print(json.dumps({'id': request.get('id', -1), 'revision': request.get('revision', -1),
                              'error': str(error)}), flush=True)


if __name__ == '__main__':
    main()
