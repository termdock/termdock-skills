# HTTP API

For callers that cannot run the CLI. The CLI is a thin wrapper over this.

```bash
curl -s -X POST -H "Authorization: Bearer $TERMINAL_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message":"build is green","sessionId":"<sessionId>"}' \
  http://127.0.0.1:3036/api/terminal/notify
```

## Request

| Field | Required | Notes |
|---|---|---|
| `message` | yes | 1 to 4000 characters after trimming |
| `sessionId` | no | Selects the session's thread on Discord. It also decides where the push goes: with a session and Discord connected, the message goes to Discord only, because that is the platform that can put it in a thread the user can answer. Omit it and the message goes to every connected remote, labelled with the workspace |
| `title` | no | Names the Discord thread, 1 to 100 characters after trimming. Only takes effect on the push that creates the thread; Telegram ignores it |

## Status codes

| Code | Body `error.code` | Meaning |
|---|---|---|
| `200` | | Delivered |
| `400` | `INVALID_NOTIFY_MESSAGE` | Empty message, message longer than 4000 characters, or `title` outside 1–100 characters |
| `401` | | Missing or invalid bearer token |
| `502` | `NOTIFY_NOT_DELIVERED` | Reached the service, went nowhere. The reason is in `error.message` |
| `503` | `REMOTE_CONTROL_UNAVAILABLE` | Remote control is not running |

**A 2xx is the only evidence the user saw anything.** Everything else means the message is still yours to deliver some other way.

## Token

The port and token come from Termdock's Terminal API settings. Token resolution, service tokens for daemons, and the rest of the surface are in the Terminal API reference (`docs/ref/api/TERMINAL-API.md` in the Termdock repository).
