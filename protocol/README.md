# ClaudeMulti WebSocket Protocol

All communication between the Mac host and Android companion uses JSON messages over a WebSocket connection. The Mac is the authoritative source of truth for session state.

Every message **must** include:
- `type` — discriminator string identifying the message kind
- `version` — integer protocol version (currently `1`)

## Message Types

| Type | Direction | Description |
|-----|-----------|-------------|
| `pair` | Android -> Mac | Initiate pairing with a 6-digit code |
| `pair_result` | Mac -> Android | Result of a pairing attempt |
| `state_sync` | Mac -> Android | Full snapshot of all sessions and screen bounds |
| `selection_changed` | Mac -> Android | Notify that the selected session changed |
| `cycle_selection` | Android -> Mac | Request to cycle the active session forward or backward |
| `send_text` | Android -> Mac | Send text input to a session |
| `request_sync` | Android -> Mac | Ask the Mac to send a fresh `state_sync` |
| `error` | Mac -> Android | Report an error condition |

## Schema

The canonical JSON Schema (draft 2020-12) lives in `schema/messages.json`. Example payloads for every message type are in `examples/`.

## Flow

1. Android connects via WebSocket and sends `pair`.
2. Mac responds with `pair_result`.
3. On success, Mac immediately sends `state_sync`.
4. Android can send `cycle_selection`, `send_text`, or `request_sync` at any time.
5. Mac pushes `selection_changed` or `state_sync` whenever state changes.
6. Mac sends `error` if something goes wrong.
