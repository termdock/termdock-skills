---
name: termdock-terminal
displayName: Termdock Terminal
description: Drive Termdock terminals and notify existing AgentSessions from inside one. Open a session for a long job, read or send terminal input, arrange panes, schedule a wake-up, or send a structured external agent callback. Use when work would otherwise block your terminal, when you need another session's output, or when an external monitor needs to notify an agent without posing as a human.
version: 28
minAppVersion: 1.23.0
---

# Drive Termdock From Inside A Terminal

You are running in a Termdock terminal. `$TERMDOCK_SESSION_ID` is your own session.

The `termdock` CLI is opt-in: the user installs it from the app, so check `$TERMDOCK_CLI_INSTALLED` before leaning on it. `1` means the CLI is on PATH and already authenticated for this machine: it mints a local token against loopback by itself. `0` means the app did not install its own shim, but a `termdock` from elsewhere may still exist: run `command -v termdock` first and use it if present. Only when the command is missing is there no workaround from inside the session (the HTTP API needs a bearer token and only the CLI mints one). Then ask the user to open **Settings -> Skills -> Command Line Tool** and press **Install**, then confirm with `command -v termdock` and continue; if the command is still missing, have them open a new session.

```bash
termdock session list --json                       # what else is running
termdock session output <id> --mode text --json    # what that session is doing
termdock session input <id> "npm test" --enter --json
```

Full command reference: `references/cli.md`. HTTP for callers that cannot run the CLI: `references/api.md`.

## What this is for

**Run a long job without blocking yourself.** A build, a migration, a dev server. Create a background session, start the job there, poll its output when you need to. Your own terminal stays responsive for the user.

```bash
id=$(termdock session create --workspace <wsId> --name build --background --json | jq -r .session.id)
termdock session input "$id" "npm run build" --enter --json
```

**Read a session that is not yours.** The user says "the other tab is stuck" and you can look, instead of asking them to paste.

**Address a tab by its name.** Session names are unique, so `termdock session output build --mode text --json` works the same as passing the id. Better than an opaque `zsh-1787...` when you are writing something a human will read.

Rename a session when its current tab name is no longer a useful address. The
response contains the actual unique name, which can gain a numeric suffix:

```bash
termdock session rename <id> build --json
```

**Arrange what the user sees.** Put the session you are talking about in front of them before you explain it.

**Schedule a wake-up.** A keep-alive rule injects a message into a session on a
schedule, for the case where work resumes later without a human to nudge it.

```bash
termdock session keepalive set <id> --rule-id wake-up --message "continue" --interval 30m --json
```

**Send an external event to an existing agent.** Use `agent callback` when a
monitor needs to notify an AgentSession without presenting the event as a new
human instruction. A shell-only terminal is not an AgentSession and is rejected;
`session input` retains its ordinary PTY typing semantics.

```bash
termdock agent callback <agent-session-id-or-tab-name> \
  --source handoff-monitor --event-kind artifact-changed \
  --dedupe-key duo-award-a --message "Duo 交付有變化，請讀取並核對。" --json
```

The callback shares that agent session's normal send queue and returns a
`deliveryId` and `createdAt`. `dedupeKey` is passed through, not deduplicated by
Termdock. These fields are untrusted collaboration metadata, not proof of sender
identity. See `references/cli.md` for flags and `references/api.md` for the HTTP
contract and delivery limits.

## What this is not for

- **Escaping your own session.** If the user asked you to do something here, do it here. Do not create a session to hide slow work.
- **Talking to yourself.** Writing input to `$TERMDOCK_SESSION_ID` feeds your own PTY and will confuse the session you are in.
- **Anything the user is watching.** Rearranging panes while they work is hostile. Change the layout when it serves the thing you were asked to do, then leave it.
- **Polling in a tight loop.** `session output --follow` streams; use it instead of a `while true` around `session output`.

## Things that will bite you

**Input is typed, not executed.** `session input` writes to the PTY exactly like a keyboard. Without `--enter` nothing is submitted. With `--enter` it submits after a delay that lets TUI apps settle, so a fast follow-up write can interleave. One command per call.

**A session running a TUI is not a shell.** If the target is running an agent, vim, or `less`, your text goes into that program, not a prompt. Read the screen first (`--mode screen`) and decide what you are actually typing into.

**`--mode` decides what you get.** `text` is the scrollback as text, `screen` is what is on the visible screen right now, `raw` keeps ANSI. For "is it waiting at a prompt", use `screen`.

**Background sessions have no visible pane.** `--mode screen` still works: it reads the session's headless screen, not the pane.

## Ports and identity

Two HTTP services, two ports, and they are not fixed. `termdock hostinfo --json` reports both plus whether you are actually inside Termdock. Never hardcode `3036` or `3033`.

`termdock identify --json` tells you which workspace, pane, and session currently has focus, which is how you find out what the user is looking at.
