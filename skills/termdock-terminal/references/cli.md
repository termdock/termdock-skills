# CLI reference

`termdock` talks to the Terminal API over loopback. Token resolution is explicit `--token`, then `TERMINAL_API_TOKEN` / `TERMDOCK_API_TOKEN`, otherwise verified-loopback cache/bootstrap provisioning. Without the local bootstrap secret it cannot verify or provision a cached token; supply one through env instead. `--url <url>` overrides the API URL, followed by `TERMDOCK_API_URL` / `TERMINAL_API_URL` / `TERMINAL_API_BASE`. Put global flags before the subcommand. A URL override does not make Termdock listen remotely; keep the server on loopback.

Most HTTP subcommands require `--json` and print the **unwrapped HTTP data**, not `{success,data}`. `session output --follow --json` prints event **NDJSON**; without `--json` it prints text. `notify` and local hook commands have optional JSON modes. Check stderr and exit code, not just whether stdout contains JSON.

The custom MCP examples preserve raw HTTP envelopes, unlike this CLI. Neither this CLI nor a read tool name creates a restricted read-only token: service scopes are only `terminal` / `agent-session`, both covering writes. Built-in Code Graph MCP exposes eight AST/code tools, not these terminal commands.

## Identity and ports

```bash
termdock identify --json    # focused workspace / pane / session
termdock hostinfo --json    # host terminal + Terminal API and AST API ports, works offline
```

Ports are not fixed. Read them from `hostinfo`, never hardcode.

## Generic tools

```bash
termdock tool --list [--json]
termdock tool <name> [--input <json> | --input-file <path>] [--json]
# Optional context, separate from the input JSON:
# --workspace-id <id> --workspace-path <path> --session-id <id>
termdock tool terminal:list
termdock tool terminal:quit-summary --input '{}'
termdock tool terminal:attach --input '{"sessionId":"persistent-term-...","expectedGeneration":1,"mode":"takeover"}'
termdock tool terminal:resize --input '{"sessionId":"persistent-term-...","cols":100,"rows":30}'
termdock tool terminal:detach --input-file detach.json
```

Omitted input defaults to `{}`; `--input` and `--input-file` are mutually exclusive. `detach.json` must contain `{ "sessionId": "persistent-term-...", "writer": { "attachmentId": "...", "generation": 2 } }`, using the writer returned by attach, not invented values. Read current generation before attaching; takeover revokes the old writer. Detach leaves the process running. This differs from the existing `session attach` SSE/stdin bridge.

`tool` always prints unwrapped JSON data, with or without `--json`. It uses the same token resolution, HTTP transport and 1 MiB byte limit as existing commands. Bad options/JSON or HTTP 4xx exit `64`; unreadable input files exit `74`; transport/HTTP 5xx exit `69`. Tool errors go to stderr. `--list` reports registered metadata, including unavailable/caller-dependent tools, not a whitelist.

Context flags become HTTP query parameters, never tool input or window identity. For remote routing use `--workspace-id`; input `workspaceId` alone is not context. Tool Runtime applies its existing checks; caller-dependent tools can refuse HTTP calls. A service token needs both `terminal` and `agent-session` scopes for this generic surface (a token with only one gets `403 FORBIDDEN_SCOPE`); the CLI's own token has both, and there are no further per-tool scope restrictions. Keep the API on loopback. See `api.md` for the shared response/error behavior.

## Workspaces

```bash
termdock workspace list --json    # workspace ids, which is what session create takes
```

## Safe dispatch queue

```bash
termdock dispatch enqueue <session-id-or-name> "next message" --workspace <id> --request-key <unique-key> --queue-timeout 60000 --json
termdock dispatch list --workspace <id> [--session <exact-id>] --json
termdock dispatch get <app-instance-id> <dispatch-id> --workspace <id> --json
termdock dispatch wait <app-instance-id> <dispatch-id> --workspace <id> --wait-timeout 120000 --json
termdock dispatch edit <app-instance-id> <dispatch-id> "edited message" --workspace <id> --expected-version <n> --json
termdock dispatch cancel <app-instance-id> <dispatch-id> --workspace <id> --json
```

Keep both handle fields from enqueue; do not invent or reuse a handle after App restart. `--workspace` is required on every operation and becomes the HTTP workspace selector, not authority. `--request-key` and `--queue-timeout` are required for enqueue. Enqueue prints `{accepted:true,dispatch:record}`; the others print the tool data. Admission is not submission, running or task completion. Reuse the request key only for the same payload from the same authenticated source. Edit requires the current version and only works while queued; 409 means refresh before trying again. Cancel after `dispatching` returns `TOO_LATE` and does not interrupt the terminal.

Check `blockReason` and `failure`. Unsupported signal modes stay queued with `unsupported-signal` until the deadline; do not send the prompt yourself as a fallback. Current auto-send support is local macOS App-owned claude/codex with verified transcript facts, a readable headless composer and no human input. Broker, unverified providers/platforms and remote paths are not promoted to supported. `unknown` with `failure.sideEffect:"possible"` means text/Enter may have reached the terminal: never replay it. `submitted` is only confirmed submission, and provider `subtype: "success"` still maps to dispatch outcome unknown. Use `dispatch wait` with an explicit integer `--wait-timeout` (0–120000 ms), no prompt. It prints the same handle and metadata plus `waitOutcome` (`state-reached`, `budget-exhausted`, `cancelled`). Waiting-human, unknown and terminal states end the foreground wait. Budget exhaustion preserves queued/blockReason or submitted/running; it is not completion or failure. Ctrl+C/CLI exit only detaches the HTTP waiter. Re-query with get or repeat wait, never enqueue again. Completed means this provider turn ended, not goal success. The UI supports Wait for turn, Move to background and Re-query dispatch. Completion tracking expires after 24 hours without stopping the terminal. See `api.md` for limits, restart errors, and authorization.

## Sessions

```bash
termdock session create --workspace <id> [--name <name>] [--background] --json
termdock session list [--workspace <id>] --json
termdock session rename <id> <name> --json
termdock session output <id> [--mode raw|text|content|screen] [--lines <n>] [--since <cursor>] --json
termdock session output <id> [--mode raw|text|content] [--lines <n>] [--since <cursor>] --follow [--json]
termdock session wait <id> --text|--gone|--regex <value> [--flags im] [--timeout <ms>] [--workspace <id>] [--authority <value>] --json
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

`session rename` returns `{ "sessionId", "name" }`. Use the returned `name`:
the global uniqueness guard may apply a `-2`, `-3`, ... suffix when another tab
already has the requested name. SSH rename only succeeds after its durable
registry write, so a reported name survives restart.

| Flag | Notes |
|---|---|
| `--background` | Creates the session without giving it a visible pane |
| `--name` | Names the tab. Use it: a name is what makes the session addressable later |
| `--mode text` | Scrollback as plain text. The default choice for "what happened" |
| `--mode screen` | What is on the screen right now. The choice for "is it waiting at a prompt". Works without a visible pane (read from the headless screen) |
| `--mode raw` | Keeps ANSI sequences |
| `--since <cursor>` | Only what arrived after that line cursor, from a previous read; supported for broker-owned `persistent-term-*` too. Check `truncated` after clear/rebuild |
| `--follow` | Streams instead of returning once, including broker-owned `persistent-term-*` attached to this Main. Ends explicitly on detach/takeover/disconnect/exit |
| `--enter` | Submits the line. Without it the text sits at the prompt unsent |

`session attach` takes over the terminal you run it in. Leave it to a human.

`session input` types; `session submit` types and waits for the echo to settle
before sending the submit key, which is what interactive TUI prompts need. Text
starting with `-` is fine for both (`session submit <id> "-y" --json`), so an
interactive prompt expecting a flag-shaped answer is reachable.
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
| `--rule-id` | The rule to write. Pass a stable id you choose (`wake-up`, `nag`) so a second run edits that rule. **Omitting it adds a new rule every run**: each session holds at most **10 enabled rules**, so a retried command without `--rule-id` eventually hits `MAX_RULES_PER_SESSION` |
| `--disabled` | Saves the rule without arming it |

All three print the rule list after the change, with `nextFireAt` per rule.
Scheduling onto a crashed or ended session is refused. Set it on the session
that should be woken, not on your own.

## External monitor callbacks to an agent

```bash
termdock agent callback <agent-session-id-or-tab-name> \
  --source <source> --event-kind <kind> --message <text> \
  [--dedupe-key <key>] [--metadata <json-object>] --json
```

The target must belong to an existing AgentSession; a shell-only tab is
rejected, never typed into. `--source`, `--event-kind`, and `--message` are
required. `--metadata` takes a JSON object. The command returns the agent
`sessionId`, a unique `deliveryId`, and ISO `createdAt`. Repeating a
`--dedupe-key` still sends another event: Termdock does not deduplicate or
automatically retry. The receipt confirms provider send, not completion of the
agent's work. After a timeout, reconcile before resending. Callback metadata
is not an authenticated sender identity. Ordinary `session input` still types
directly into a terminal and does not add callback metadata.
An OpenCode daemon callback waits up to 30 seconds for the current turn to
finish; if it is still busy, the command reports
`AGENT_SESSION_CALLBACK_CONFLICT` without interrupting that turn.

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
shape, where a pane carries `id`, `terminalId`, and an optional `contentType`
(#2150). Restore matches panes on their content bindings, which the slim shape
does not have, so restoring one would apply the layout and leave every pane
unbound. `layout restore` rejects a slim file rather than doing that, but the
fix is at capture time. File panes in a slim snapshot are now reported under
`restored.skipped` with `contentType: "file"` instead of being silently dropped.
Browser panes (`contentType: "browser"`) behave the same way; in a `--full`
snapshot they restore like any other binding while that browser tab is still open.

```bash
termdock layout get --full --json > /tmp/layout.json
# rearrange, then put it back
termdock layout restore --file /tmp/layout.json --json
```

Layout types are the ones the app offers (`single`, `horizontal-2`, `vertical-2`, `quad`, and the 1-plus-2 variants). `layout get` tells you what exists now, including pane ids.

## Notifying the user

```bash
termdock notify <message> [--session <id>] [--title <text>] [--json]
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
| `64` | The request was rejected: either a usage error (unknown flag, missing value, wrong argument shape), or Termdock answered with a 4xx such as `SESSION_NOT_FOUND` or `MAX_RULES_PER_SESSION`. Stderr says which: API rejections start with `Termdock Terminal API error:` |
| `69` | Termdock did not give a usable answer: unreachable, or it answered with a 5xx. `notify` returning "not delivered" lands here too |
| other non-zero | Other failure. The reason is on stderr |

Check the exit code. A failed call prints the reason to stderr, not stdout, so a pipeline that only reads stdout sees nothing and carries on.

Live Prompt library references are configured through the scheduling UI or the
HTTP keep-alive API (`rule.promptRef`); the CLI `--message` flag remains inline
text. See `api.md` for the reference payload and target-workspace rules.

## Local terminal ownership (`persistent-term-*`)

- Local workspace create defaults to broker ownership on desktop, split panes, HTTP, CLI and Tool Runtime. Terminals keep running after App Quit; there is no user-facing persistent mode or special creation entry. Existing live App-owned processes are not migrated.
- `terminal:create` and HTTP create accept `persistence?: "app" | "broker"`: omitted means automatic broker with silent App-owned fallback; `app` explicitly selects App-owned lifetime; `broker` requires the broker and reports failure rather than falling back. No new CLI flag is added.
- Capability unavailable, blocked Windows Job, broker unreachable/incompatible or unsupported exact launch options fall back before a native effect. Custom env/cwd/shell, persisted logs and dimensions unsupported by an older broker retain the App-owned capability. Unknown sent-create outcomes never open a second shell. Remote/peer/SSH workspaces retain their remote owner.
- The default create pipeline grants this Main the writer. Input/submit/key/interrupt/resize require that grant and fence stale queued calls; they never take over another client implicitly. Without a valid lease a write returns 409 `STALE_ATTACHMENT`, and rejected input is not retried. Keep-alive and submissions share the ordinary submit chain; `queueUntilReady` and agent submissions use existing readiness logic. CLI `session attach` remains the SSE/stdin bridge, not a broker writer grant.
- Output uses the same bounded Main projection for renderer and agent reads: `raw` retains ANSI rows; `text`/`content` use App-owned normalization and chrome filtering. Numeric `cursor`/`nextCursor` are App-style line cursors: pass `nextCursor` to `--since` or SSE `since` for the next read. Clear, attachment rebuild or an expired history window returns `truncated:true`; resume from the returned cursor. `snapshotCursor` remains the separate broker source cursor. Follow/SSE and `wait-output` require this Main's attachment and end with `output.error` on takeover/detach (`STALE_ATTACHMENT`), broker disconnect (`BROKER_UNREACHABLE`) or session end (`SESSION_ENDED`, reported only after the retained output has been delivered). CLI follow writes that event in JSON mode and exits nonzero. Reads do not acquire or steal a writer. A session this Main is not attached to (taken over, detached or never attached) is read from a broker snapshot: whenever new output has arrived the line projection is rebuilt, so a `since` read returns the whole retained window with `truncated:true` instead of an increment. An unterminated last row is delivered as it stands; text that later completes that same row is not re-sent, as with App-owned terminals. `screen` still uses the shared headless projection and hash/window rules, with no incremental cursor semantics; `source=dom` remains unsupported. The default window is 50 lines; `ifHash` remains available.
- Names resolve through the ordinary terminal name namespace. Unified protocol v1.1 supports authoritative writer-fenced rename, names up to 200 characters, shell process evidence, dimensions 500×100 and optional bounded error hints. Only v1.1/v1.0 are negotiated. v1.0 has no name/rename/process-evidence/error-message extensions and retains 240×100; new fields are stripped from old-client replies/events/deduplicated results. v1.1-only sessions require a compatible client; old broker rename returns `RENAME_UNSUPPORTED`.
- Closing a desktop tab or `session destroy` terminates its shell and children and waits for process-tree acknowledgement. A `lost` session (its broker instance is gone) cannot be terminated; destroy only forgets it locally and returns `treeReaped:false, forgotten:true`. Quit/Cmd+R and explicit `terminal:detach` do not terminate them. There is no session-count cap. The broker warns at 192 MiB RSS and refuses new creation at 256 MiB (`RESOURCE_LIMIT`), without terminating existing work. PTY/process exhaustion returns `RESOURCE_LIMIT` with a readable recovery hint from a v1.1 broker; other spawn failures return `CAPABILITY_UNAVAILABLE`.
- Startup uses the one savedSessions/layout: living processes reconnect in their original pane/order; confirmed ended/missing processes rebuild with a NEW ID, saved history and keep-alive rules. Unreachable/incompatible broker panes stay in place for retry; other writers remain read-only until confirmed takeover. Manual `terminal:restore-persistent {sessionId}` is Tool Runtime only (no HTTP/CLI route), returns `{snapshot, broker, session?, errorCode?}` and does not accept caller cwd/shell or replay uncertain create. Existing App-owned snapshots retain snapshot-only restore.
- Read-only `terminal:quit-summary {}` returns App-ending/background-running counts; a broker count of `null` is unknown, not zero. Broker mutations are never automatically retried. `name` is broker-held metadata; `paneId`/`stealFocus` use ordinary desktop placement, and `background:true` cannot be combined with placement.

## Current-screen condition waits (v1.24)

```bash
termdock session wait shell --text 'done' --json
termdock session wait shell --gone 'working' --timeout 0 --json
termdock session wait shell --regex '^中文.*done$' --flags im --timeout 30000 --json
```

Choose one condition flag. `text`/`gone` are case-sensitive literals, not regex; initial absence satisfies `gone`, regardless of old history. Regex uses implicit Unicode `u`, plus optional `i`/`m` once each. Empty values and other flags are rejected. This checks the complete current screen (headless first, renderer fallback), never history. A match is not task-completion evidence.

`--timeout` defaults to 30000 ms, accepts finite nonnegative values up to 120000 without clamping, and `0` checks once. `--workspace` and `--authority` are optional expected identity checks, not authority grants. App authority is `app`; broker authority is `broker:<attachmentId>`. The name resolves once; exit, rebuild or attachment change cannot redirect an old wait to a replacement.

The unwrapped result includes `sessionId`, `kind`, `matched`, `timedOut` and `observation` (`source`, `generation`, `snapshotVersion`, or null if no snapshot completed). Normal expiry returns `matched:false,timedOut:true`; cancellation/revocation/target change are errors. Limits are 16 waiters per session, 128 globally, 1024 UTF-8 value bytes and a 256 KiB full-screen matching window. Oversized/unavailable screens fail instead of producing a false `gone` match. Regex runs only in terminating workers (two units, 50 ms per evaluation, queue time included in the deadline).

Peer/SSH without the screen lease capability returns `CAPABILITY_UNAVAILABLE`, without local fallback. Broker initial/one-shot snapshots do not acquire a writer; a nonmatching continuous wait requires this Main's attachment. Stable API error codes are printed on stderr, including `INVALID_REGEX`, `UNSUPPORTED_REGEX_FLAGS`, `REGEX_TIMEOUT`, `REGEX_WORKER_UNAVAILABLE`, `RESOURCE_LIMIT`, `SNAPSHOT_TOO_LARGE`, `SCREEN_READ_UNAVAILABLE`, `SCREEN_READ_FAILED`, `CANCELLED`, `AUTHORITY_REVOKED` and `TARGET_CHANGED`. HTTP 4xx exits 64; transport/5xx exits 69. See `api.md` for the complete request/error contract.
