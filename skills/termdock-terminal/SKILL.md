---
name: termdock-terminal
displayName: Termdock Terminal
description: Drive Termdock terminals from inside one. Open a session for a long job instead of blocking your own, read what another session is doing, send input to it, arrange panes, and schedule a wake-up. Use when work would otherwise block your terminal, when you need output from a session that is not yours, or when the user asks you to run something "in another tab".
version: 6
minAppVersion: 1.21.0
---

# Drive Termdock From Inside A Terminal

You are running in a Termdock terminal. The `termdock` CLI is on PATH and already authenticated for this machine: it mints a local token against loopback by itself. `$TERMDOCK_SESSION_ID` is your own session.

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

**Arrange what the user sees.** Put the session you are talking about in front of them before you explain it.

**Schedule a wake-up.** A keep-alive rule injects a message into a session on a
schedule, for the case where work resumes later without a human to nudge it.

```bash
termdock session keepalive set <id> --rule-id wake-up --message "continue" --interval 30m --json
```

## What this is not for

- **Escaping your own session.** If the user asked you to do something here, do it here. Do not create a session to hide slow work.
- **Talking to yourself.** Writing input to `$TERMDOCK_SESSION_ID` feeds your own PTY and will confuse the session you are in.
- **Anything the user is watching.** Rearranging panes while they work is hostile. Change the layout when it serves the thing you were asked to do, then leave it.
- **Polling in a tight loop.** `session output --follow` streams; use it instead of a `while true` around `session output`.

## Things that will bite you

**Input is typed, not executed.** `session input` writes to the PTY exactly like a keyboard. Without `--enter` nothing is submitted. With `--enter` it submits after a delay that lets TUI apps settle, so a fast follow-up write can interleave. One command per call.

**A session running a TUI is not a shell.** If the target is running an agent, vim, or `less`, your text goes into that program, not a prompt. Read the screen first (`--mode screen`) and decide what you are actually typing into.

**`--mode` decides what you get.** `text` is the scrollback as text, `screen` is what is on the visible screen right now, `raw` keeps ANSI. For "is it waiting at a prompt", use `screen`.

**Background sessions have no visible pane.** That is the point, but `--mode screen` needs the pane; use `text`.

## Ports and identity

Two HTTP services, two ports, and they are not fixed. `termdock hostinfo --json` reports both plus whether you are actually inside Termdock. Never hardcode `3036` or `3033`.

`termdock identify --json` tells you which workspace, pane, and session currently has focus, which is how you find out what the user is looking at.
