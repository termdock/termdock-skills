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
| `sessionId` | no | Only decides the label. Omit it and the message is labelled with the workspace |

## Status codes

| Code | Body `error.code` | Meaning |
|---|---|---|
| `200` | | Delivered |
| `400` | `INVALID_NOTIFY_MESSAGE` | Empty message, or longer than 4000 characters |
| `401` | | Missing or invalid bearer token |
| `502` | `NOTIFY_NOT_DELIVERED` | Reached the service, went nowhere. The reason is in `error.message` |
| `503` | `REMOTE_CONTROL_UNAVAILABLE` | Remote control is not running |

**A 2xx is the only evidence the user saw anything.** Everything else means the message is still yours to deliver some other way.

## Token

The port and token come from Termdock's Terminal API settings. Token resolution, service tokens for daemons, and the rest of the surface are in the Terminal API reference (`docs/ref/api/TERMINAL-API.md` in the Termdock repository).
