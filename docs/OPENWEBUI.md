# Open WebUI chat

The chat uses the shell's native typography and surfaces. User prompts retain
their literal whitespace; assistant replies use `K4.MarkdownView`. Thinking is a
compact disclosure, expanded only on request. The model must provide reasoning;
the client never invents it. Durations are measured locally for live requests.

## Interaction

- Enter sends; Shift+Enter inserts a newline. Composition with an IME is respected.
- Copy and edit actions appear on message hover or keyboard focus.
- Editing starts a new active branch; previously saved branches remain in history.
- Selecting text or scrolling upward pauses following. The down arrow returns to
  the newest content, including a response that is still arriving.
- Stop preserves partial text and reasoning. Failed/stopped turns offer Retry.
- Selection and screenshot attachments belong to the next prompt. Screenshots
  use separate files, so capturing another does not replace an earlier preview.
- Raw code is copied, including long blocks, through stdin rather than argv.

## API flow

The integration uses Bearer authentication with `GET /api/models` and
`POST /api/chat/completions`. Each completion sends the full active conversation
and consumes HTTP SSE, or JSON when a server/model forces non-streaming output.
The transport accepts SSE comments, multiline data, UTF-8, finish reasons and
structured errors. Dedicated reasoning fields and recognized reasoning wrappers
are presented separately from the answer; literal code examples remain literal.

Chat persistence is a separate operation using `/api/v1/chats/new` and
`/api/v1/chats/{id}`. Completion requests omit WebSocket routing identifiers.
Saved messages retain their tree links, model attribution and reasoning metadata.
Generation and history callbacks are scoped to the originating request/chat.
History synchronization failures are shown inline and retried on the next save.

Open WebUI's outlet behavior differs across releases. This client displays the
direct completion body and does not promise outlet-filtered output: on stable
releases outlets require `/api/chat/completed`; on development releases outlets
may already run inline, and that still does not rewrite the HTTP response. An
unconditional second call would risk duplicate filter side effects.

References checked for this implementation:
- https://docs.openwebui.com/reference/api-endpoints
- https://docs.openwebui.com/reference/api-flow

## Checks

Run `python3 tools/test_openwebui.py` with Mistune and Pygments available, and
`python3 tools/test_openwebui_ui.py` with Quickshell/QtTest available (the Nix dev
shell supplies dependencies). Tests use isolated state and synthetic content.
