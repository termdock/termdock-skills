# Delivery: failures, limits, and the HTTP surface

Read this when a send failed, or when the caller is not a Termdock terminal.

## Why a send was rejected

A non-zero exit code means the user did not get the message. The reason is on
stderr. None of them are worth retrying in a loop.

| Reason | What it means | What to do |
|---|---|---|
| `Rate limit reached (6 messages per minute for <id>)` | You are sending too often for one session | Batch what you were going to say and send once, later |
| `Push notifications are disabled in Settings.` | The user turned pushes off | Respect it. Do not look for another channel |
| `No push notification provider is connected.` | Nothing configured, or the provider failed to start | Nothing you can fix from here |
| `Remote control is disabled in Settings.` | The whole feature is off | Same |
| `Remote control is not running` (HTTP 503) | The service is not up yet | Same |

The rate limit counts per session per rolling minute. Messages that get rejected
are not counted, so a stopped caller is not punished for having tried.

## Naming the source

The label next to the message is the terminal tab's name, resolved from the
session. Inside a Termdock terminal it comes from `$TERMDOCK_SESSION_ID`, which
the terminal sets for you.

A caller that is not a Termdock terminal (a daemon, a cron script, a hook) has no
such session and must say what it is talking about:

```bash
termdock notify "nightly build failed" --session <sessionId>
```

Without a session the message still goes out, labelled with the workspace name
instead of a tab.

## HTTP

The CLI is a thin wrapper. Callers that cannot run it use the endpoint directly:

```bash
curl -s -X POST -H "Authorization: Bearer $TERMINAL_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"message":"build is green","sessionId":"<sessionId>"}' \
  http://127.0.0.1:3036/api/terminal/notify
```

Status codes:

- `200` delivered
- `400` `INVALID_NOTIFY_MESSAGE`: empty, or longer than 4000 characters
- `502` `NOTIFY_NOT_DELIVERED`: reached the service, went nowhere. The reason is
  in the error message
- `503` `REMOTE_CONTROL_UNAVAILABLE`: remote control is not running

**A 2xx is the only evidence the user saw anything.** Everything else means the
message is still yours to deliver some other way.

Token resolution, ports, and the rest of the API are in the Terminal API
reference (`docs/ref/api/TERMINAL-API.md` in the Termdock repo).
