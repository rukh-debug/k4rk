#!/usr/bin/env python3
"""One immutable chat request on stdin; normalized completion events on stdout."""

import base64
import json
import mimetypes
import sys
import urllib.error
import urllib.request


def emit(event):
    print(json.dumps(event, ensure_ascii=False), flush=True)


def error_text(value):
    if isinstance(value, dict):
        return str(value.get('message') or value.get('detail') or value)
    return str(value)


def normalize(event):
    if event.get('error') or event.get('detail'):
        return {'type': 'error', 'message': error_text(event.get('error') or event['detail'])}
    choices = event.get('choices') or []
    if not choices:
        return None
    choice = choices[0]
    full = 'message' in choice
    delta = choice.get('message') if full else choice.get('delta')
    delta = delta or {}
    content = delta.get('content') or ''
    if isinstance(content, list):
        content = ''.join(part.get('text', '') for part in content if part.get('type') == 'text')
    reasoning = delta.get('reasoning_content') or delta.get('reasoning') or delta.get('thinking') or ''
    return {'type': 'message' if full else 'delta', 'content': content,
            'reasoning': reasoning if isinstance(reasoning, str) else '',
            'finish': choice.get('finish_reason') or ''}


def events(response):
    """SSE events may have several data lines, comments, and no space after ':'."""
    data = []
    for raw in response:
        line = raw.decode('utf-8').rstrip('\r\n')
        if not line:
            if data:
                yield '\n'.join(data)
                data = []
        elif line.startswith('data:'):
            value = line[5:]
            data.append(value[1:] if value.startswith(' ') else value)
    if data:
        yield '\n'.join(data)


def attach_images(payload):
    attached = []
    for index, message in enumerate(payload.get('messages', [])):
        path = message.pop('local_image', '')
        if not path:
            continue
        with open(path, 'rb') as image:
            encoded = base64.b64encode(image.read()).decode('ascii')
        mime = mimetypes.guess_type(path)[0] or 'image/png'
        content = message.get('content') or ''
        message['content'] = (content if isinstance(content, list) else [{'type': 'text', 'text': content}]) + [
            {'type': 'image_url', 'image_url': {'url': 'data:' + mime + ';base64,' + encoded}}]
        attached.append({'index': index, 'content': message['content']})
    return attached


def run(request):
    payload = request['payload']
    attached = attach_images(payload)
    if attached:
        emit({'type': 'attachments', 'messages': attached})
    http = urllib.request.Request(
        request['url'].rstrip('/') + '/api/chat/completions',
        data=json.dumps(payload).encode('utf-8'),
        headers={'Content-Type': 'application/json', 'Accept': 'text/event-stream, application/json',
                 'Authorization': 'Bearer ' + request['token']}, method='POST')
    with urllib.request.urlopen(http, timeout=300) as response:
        if 'text/event-stream' in response.headers.get('Content-Type', ''):
            finished = False
            for data in events(response):
                if data.strip() == '[DONE]':
                    emit({'type': 'done'})
                    return
                event = normalize(json.loads(data))
                if event:
                    emit(event)
                    finished = finished or bool(event.get('finish')) or event['type'] == 'error'
            if not finished:
                emit({'type': 'error', 'message': 'The stream ended before the response completed.'})
        else:
            event = normalize(json.load(response))
            if event:
                emit(event)
        emit({'type': 'done'})


def main():
    try:
        run(json.loads(sys.stdin.readline()))
    except urllib.error.HTTPError as error:
        body = error.read().decode('utf-8', 'replace')
        try:
            value = json.loads(body)
            detail = error_text(value.get('detail') or value.get('error') or value)
        except ValueError:
            detail = body[:300] or error.reason
        emit({'type': 'error', 'message': f'HTTP {error.code}: {detail}'})
    except Exception as error:
        emit({'type': 'error', 'message': str(error)})


if __name__ == '__main__':
    main()
