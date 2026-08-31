# CLI reference

`termdock` talks to the Terminal API over loopback and mints its own token there, so nothing needs configuring on the machine running Termdock. Everything below takes `--url <url>` and `--token <token>` if you are pointing at another machine.

Most subcommands require `--json` and print one JSON object. `notify` is the exception; `--json` is optional there.

## Identity and ports

```bash
termdock identify --json    # focused workspace / pane / session
termdock hostinfo --json    # host terminal + Terminal API and AST API ports, works offline
```

Ports are not fixed. Read them from `hostinfo`, never hardcode.

## Workspaces

```bash
termdock workspace list --json    # workspace ids, which is what session create takes
```

## Sessions

```bash
termdock session create --workspace <id> [--name <name>] [--background] --json
termdock session list [--workspace <id>] --json
termdock session output <id> [--mode raw|text|content|screen] [--lines <n>] [--since <cursor>] --json
termdock session output <id> [--mode raw|text|content] [--lines <n>] [--since <cursor>] --follow [--json]
termdock session input <id> <text> [--enter] --json
termdock session submit <id> <text> [--settle-ms <n>] [--queue-until-ready] [--ready-timeout <ms>] --json
termdock session key <id> <key> --json
termdock session interrupt <id> --json
termdock session status <id> --json
termdock session log <id> --json
termdock session ports <id> --json
termdock session attach <id>
termdock session destroy <id> --json
```

`<id>` accepts a session id or a tab name; names are unique.

| Flag | Notes |
|---|---|
| `--background` | Creates the session without giving it a visible pane |
| `--name` | Names the tab. Use it: a name is what makes the session addressable later |
| `--mode text` | Scrollback as plain text. The default choice for "what happened" |
| `--mode screen` | What is on the visible screen right now. The choice for "is it waiting at a prompt". Needs a visible pane |
| `--mode raw` | Keeps ANSI sequences |
| `--since <cursor>` | Only what arrived after that cursor, from a previous read |
| `--follow` | Streams instead of returning once |
| `--enter` | Submits the line. Without it the text sits at the prompt unsent |

`session attach` takes over the terminal you run it in. Leave it to a human.

`session input` types; `session submit` types and waits for the echo to settle
before sending the submit key, which is what interactive TUI prompts need.
`session key` sends one named key (`up`, `enter`, `ctrl+c`, ...) and
`session interrupt` is Ctrl+C without destroying the session.

`session status` answers "is it still working" without reading output;
`session ports` reports what the processes in that session are listening on,
which beats grepping the scrollback for a dev server URL.

## Scheduling a wake-up (keep-alive)

```bash
termdock session keepalive list <id> --json
termdock session keepalive set <id> --rule-id <id> --message <text> \
  (--interval 30m | --idle 15m | --daily 09:00) [--disabled] --json
termdock session keepalive rm <id> <rule-id> --json
```

A rule injects the message into that session on a schedule, with Enter, so it is
submitted. Durations need a unit (`90s`, `30m`, `2h`); a bare number is rejected.

| Flag | Notes |
|---|---|
| `--interval` | Every interval from when the rule was saved |
| `--idle` | Once per idle period, after the session has been idle that long. Local sessions only |
| `--daily` | Once a day at `HH:MM` local time |
| `--rule-id` | The rule to write. Pass a stable id you choose (`wake-up`, `nag`) so a second run edits that rule. **Omitting it adds a new rule every run**: there is no per-session cap, so a retried command stacks duplicates that all fire |
| `--disabled` | Saves the rule without arming it |

All three print the rule list after the change, with `nextFireAt` per rule.
Scheduling onto a crashed or ended session is refused. Set it on the session
that should be woken, not on your own.

## Layout

```bash
termdock layout get [--full] --json
termdock layout set <type> [--sessions <id,id>] --json
termdock layout assign <pane-id> <session-id|none> --json
termdock layout activate <pane-id> --json
termdock layout activate-panel <panel-id> --json
termdock layout restore --file <path> --json
```

`activate` focuses a pane, `activate-panel` focuses a tab, which is the one to
use for a background tab with no pane.

**Save with `--full` if you intend to restore.** Without it you get the slim
shape, where a pane carries only `id` and `terminalId`. Restore matches panes on
their content bindings, which the slim shape does not have, so restoring one
would apply the layout and leave every terminal unbound. `layout restore`
rejects a slim file rather than doing that, but the fix is at capture time:

```bash
termdock layout get --full --json > /tmp/layout.json
# rearrange, then put it back
termdock layout restore --file /tmp/layout.json --json
```

Layout types are the ones the app offers (`single`, `horizontal-2`, `vertical-2`, `quad`, and the 1-plus-2 variants). `layout get` tells you what exists now, including pane ids.

## Notifying the user

```bash
termdock notify <message> [--session <id>] [--json]
```

Pushes to the Discord/Telegram remote the user configured. Session defaults to `$TERMDOCK_SESSION_ID`. See the `termdock-notify` skill for when this is appropriate; it is not for progress narration.

## Agent session hooks

```bash
termdock hooks status    [--agent claude|codex|gemini] [--json]
termdock hooks setup     [--agent claude|codex|gemini] [--dry-run] [--json]
termdock hooks uninstall [--agent claude|codex|gemini] [--dry-run] [--json]
termdock hook ingest --json [--wait] [--wait-timeout <ms>] [--request-timeout <ms>]
```

`hooks setup` writes the hook configuration for an agent CLI so its permission prompts and questions surface in Termdock. `hook ingest` is what the hook itself calls; you do not call it by hand.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Success |
| `64` | Usage error: unknown flag, missing value, wrong argument shape |
| `69` | Termdock did not give a usable answer: unreachable, or it answered with a 5xx. `notify` returning "not delivered" lands here too |
| other non-zero | Other failure. The reason is on stderr |

Check the exit code. A failed call prints the reason to stderr, not stdout, so a pipeline that only reads stdout sees nothing and carries on.
