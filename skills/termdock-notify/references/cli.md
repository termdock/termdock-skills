# CLI

```
termdock notify <message> [--session <id>] [--json]
```

## Options

| Option | Effect |
|---|---|
| `--session <id>` | Which terminal the message is labelled with. Defaults to `$TERMDOCK_SESSION_ID`, which Termdock sets in every terminal it opens |
| `--json` | Print the response body instead of one line. Optional, unlike other `termdock` subcommands |

No token or URL is needed on the machine running Termdock: the CLI mints a local service token against loopback by itself.

## Exit codes

`0` means the user got it. Anything else means they did not.

| Code | Meaning |
|---|---|
| `0` | Delivered |
| `64` | Bad usage (no message, `--session` with no value) |
| non-zero, other | Not delivered. The reason is on stderr |

## Why a send was rejected

None of these are transient. Do not retry in a loop.

| Reason on stderr | What it means | What to do |
|---|---|---|
| `Rate limit reached (6 messages per minute for <id>)` | Too many sends for one session in a rolling minute | Batch what you were going to say, send once, later |
| `Push notifications are disabled in Settings.` | The user turned pushes off | Respect it. Do not look for another channel |
| `No push notification provider is connected.` | Nothing configured, or the provider failed to start | Nothing you can fix from here |
| `Remote control is disabled in Settings.` | The whole feature is off | Same |
| `Remote control is not running` | The service is not up | Same |

Rejected messages are not counted against the rate limit, so a caller that stops when told is not punished for having tried.

## Outside a Termdock terminal

A daemon, cron job, or hook has no `$TERMDOCK_SESSION_ID` and must say what it is talking about:

```bash
termdock notify "nightly build failed" --session <sessionId>
```

Without a session the message still goes out, labelled with the workspace name instead of a terminal tab.
