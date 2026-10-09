# HTTP API reference

For callers that cannot run the CLI. The CLI is a thin wrapper over these.

Base URL is `http://127.0.0.1:<port>`; get the port from `termdock hostinfo --json`. Terminal/session requests need `Authorization: Bearer <token>`. Service scopes are only `terminal` and `agent-session`; both allow writes and do not restrict workspace/session IDs. AST HTTP uses separate auth configuration.

```bash
curl -s -H "Authorization: Bearer $TERMINAL_API_TOKEN" \
  "http://127.0.0.1:$PORT/api/terminal/sessions"   # PORT from services.terminalApi.port
```

## Generic Tool Runtime entry

`GET /api/tools` lists the registered tools using the same discovery as renderer `tool:discover`. Data is an array of `{name,category,isReadOnly,isConcurrencySafe,isAvailable}`. Discovery includes unavailable tools and caller-dependent tools; it is not an external-call whitelist or a guarantee that a call will succeed.

`POST /api/tools/:name` calls that tool directly. URL-encode the tool name; the JSON body is the tool input itself, not `{name,input}`. Optional query parameters `workspaceId`, `workspacePath`, and `sessionId` supply ToolContext separately. Omitted `workspacePath` is `""`. Input fields are not copied into context. Context uses `invocationOrigin:"http"` and has no window `caller`; workspace routing, root claims, validation and permissions remain the tool/registry's responsibility. For remote workspace calls, supply context `workspaceId`; an input `workspaceId` alone is not routing context. Peer/SSH capabilities and offline failures remain governed by Tool Runtime, with no local fallback added here.

Both endpoints use the existing Terminal API bearer-token validation and enabled gate. Because the registry holds tools from both scope domains, a service token must hold **both** `terminal` and `agent-session` scopes; a token with only one (for example the read-only MCP adapter's `terminal`-only token) gets `403 FORBIDDEN_SCOPE`. Tokens minted by the CLI and tokens created without `scopes` hold both. There are no per-tool scope checks beyond that: the tool decides whether the operation is allowed. Keep it on loopback; never expose it through the webhook tunnel.

Responses use the existing HTTP ToolResult conversion: `{success:true,data}` or `{success:false,error:{code,message}}`. Known terminal errors, including a recognized `errorCode` from the registry or tool, retain their HTTP status; validation errors return `400 INVALID_TOOL_INPUT`; an unknown tool name returns `404 TOOL_NOT_FOUND`. Errors without a recognized terminal code return `500 TOOL_CALL_FAILED`, preserving the registry/tool error message. An unavailable registry returns `503 TOOL_RUNTIME_UNAVAILABLE`. The existing 1 MiB request-body limit applies. There is no new input/result adaptation or tool-specific authorization in this route. Tools requiring a renderer caller, such as `peer:host-terminal-view-intents`, return their own rejection. Calls are unary, not event subscriptions; the generic endpoint does not provide renderer cancellation/progress channels.

```bash
curl -s -H "Authorization: Bearer $TERMINAL_API_TOKEN" \
  "http://127.0.0.1:$PORT/api/tools"
curl -s -H "Authorization: Bearer $TERMINAL_API_TOKEN" -H 'Content-Type: application/json' \
  -d '{}' "http://127.0.0.1:$PORT/api/tools/terminal%3Alist"
```

Persistent writer handoff uses the same entry, not a new dedicated route. Read the session's current generation first. `terminal:attach` input is `{sessionId,expectedGeneration,mode:"takeover"}` (or `"if-unowned"`); retain its returned `writer:{attachmentId,generation}`. Then call `terminal:resize {sessionId,cols,rows}` and `terminal:detach {sessionId,writer}`. Takeover revokes the previous writer. Detach preserves the process; later I/O may acquire an unowned writer through the existing tool logic, so detach is not a permanent write prohibition. `terminal:quit-summary {}` reports quit counts. CLI `session attach` remains the old SSE/stdin bridge and does not grant a broker writer. Do not blindly retry uncertain mutations.

## Terminal sessions

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/terminal/workspaces` | Workspaces, and their ids for creating sessions |
| `POST` | `/api/terminal/sessions` | Create. Body takes `workspaceId`, `name`, `background` |
| `GET` | `/api/terminal/sessions` | List. `?workspaceId=` filters |
| `PATCH` | `/api/terminal/sessions/:id` | Rename. Body is `{ "name": "..." }`; returns the applied `{ "sessionId", "name" }` |
| `GET` | `/api/terminal/sessions/:id/status` | Activity, whether it is waiting at a prompt |
| `GET` | `/api/terminal/sessions/:id/output` | Read. `?mode=raw\|text\|content\|screen`, `?lines=`, `?since=` (App-style line cursor, including broker-owned `persistent-term-*`; inspect `truncated`) |
| `GET` | `/api/terminal/sessions/:id/events` | Same content as an SSE stream, including broker-owned `persistent-term-*` attached to this Main; `output.error` ends lost/ended attachments |
| `GET` | `/api/terminal/sessions/:id/log` | The persisted session log on disk |
| `GET` | `/api/terminal/sessions/:id/ports` | Ports the processes in that session are listening on |
| `POST` | `/api/terminal/sessions/:id/input` | Write to the PTY. `data`, `appendEnter`, `submitKey` |
| `POST` | `/api/terminal/sessions/:id/submit` | Submit interactive input, waiting for the echo to settle |
| `POST` | `/api/terminal/sessions/:id/keys` | Send a named key (`up`, `enter`, `ctrl+c`, ...) |
| `POST` | `/api/terminal/sessions/:id/interrupt` | Ctrl+C |
| `DELETE` | `/api/terminal/sessions/:id` | Destroy |
| `GET` | `/api/terminal/sessions/:id/keepalive` | Scheduled injections (keep-alive) for that session |
| `PUT` | `/api/terminal/sessions/:id/keepalive` | Create or replace one rule, addressed by `rule.id` |
| `DELETE` | `/api/terminal/sessions/:id/keepalive/:ruleId` | Remove one rule |

`:id` accepts a session id or a tab name. So do the layout endpoints below:
`sessionIds`, the `assign` body's `sessionId`, and the `contentId` of each
`terminal` pane in a restore snapshot.

### Exact workspace reads (1.23.0)

`GET /sessions/:id/status` and `GET /sessions/:id/output?mode=text` accept
`x-termdock-workspace-id: <expected-workspace-id>`. With this header, both HTTP
and Tool Runtime bypass name resolution and check the live exact ID, workspace
ownership, workspace existence and online state in the existing service at read
time. Success adds `workspaceId` to `data.session` (status) or `data` (output).
Missing/moved IDs or deleted workspaces return 404, offline sessions return 409,
and output modes other than text or `waitForChange` return 400. Without the
header, existing name-addressing behavior is unchanged. This guard is not an
authorization grant and does not narrow the underlying token's scopes.

For the four-tool supplied-token-only adapter, use the separate executable
`termdock-readonly-mcp --config <file>`, not the CLI subprocess. Setup, strict
allowlists, bounded cursors, error codes and supported versions are documented
in `docs/ref/api/READONLY-MCP.md`. Its sole token source is the dedicated
`TERMDOCK_MCP_TOKEN` setup variable; it never provisions or reads the CLI cache.

Name resolution: an id wins over a name; a name matching several sessions is not
guessed at, it comes back as `SESSION_NOT_FOUND` with the closest candidate names.
`SESSION_RESOLVE_FAILED` is a different failure, the resolution step itself broke
and nothing was touched. Resolution happens once per request, and `/events` locks
the id at subscribe time, so a tab renamed mid-flight can take a write meant for
whoever holds the name now. Resolve once and address the id when that matters.
`assign` echoes the resolved id back as `terminalId`. `restore` lists a snapshot
target in `restored.unresolvedTargets` only when it is neither a live session id,
nor a unique tab name, nor shaped like a session id (`zsh-`, `terminal-pty-`,
`peer-term-`, `ssh-term-`). That combination means it was never an address. An id
whose session already ended is the renderer's `skipped: CONTENT_NOT_FOUND` instead.
`activePanelId` resolves the same way, so a unique tab name works there too; it
never enters `unresolvedTargets` because it can also legitimately be a file panel
id, and a value that does not resolve is passed through, with the response's
`activePanelId` reporting the focus actually kept.

Rename uses the same global uniqueness guard as the UI. The returned `name` is
the address to retain: a collision adds a `-2`, `-3`, ... suffix. SSH rename
waits for its durable registry write before success; persistence failure returns
`PERSIST_FAILED` instead of advertising a name that disappears after restart.

`/input` answers with a `requestId` once the request reaches input handling:
`data.requestId` on success, `error.details.requestId` on failure (400
`INVALID_INPUT_DATA` and auth rejections carry none). The same id is on Termdock's `/input`
transaction log line with per-stage timings, so quoting it reconstructs that
one request's lifecycle when a write seems lost or stalled. Sub-second
successful data-only writes are the one case that is not logged. A PTY write
that throws answers `500 TERMINAL_WRITE_FAILED`, still with `error.details.stage`
(`lock` / `readiness` / `chain` / `write`) and
`error.details.requestId`; a session destroyed while queued, or between the text and
the submit key, answers
`404 SESSION_NOT_FOUND` instead.

While a remote peer holds a session it created on this machine, `/input`,
`/submit`, `/keys` and `/interrupt` answer `409 SESSION_HELD_BY_PEER` and write
nothing (`/input` keeps its `requestId`). Do not retry on a loop: the same
request only succeeds after the session is taken over on this machine.

A keep-alive rule is `{"rule":{"id","enabled","schedule","message"}}`, where
`schedule` is `{"kind":"interval","intervalMs":n}`,
`{"kind":"idle","thresholdMs":n}` or `{"kind":"daily","time":"HH:mm"}`. All
three respond with the rule list after the change. The message is injected with
Enter, so it is submitted.

Each session holds at most **10 enabled rules**. Adding an eleventh enabled rule with a new `id` is
rejected with `400 MAX_RULES_PER_SESSION`. Updating an existing rule (same `id`) does
not count against the limit. Disabled rules do not count; delete rules you no longer need.

Failures: `400 INVALID_TOOL_INPUT` when the rule body fails the schema (a
missing field, or a schedule that is not one of the three kinds), `400
MAX_RULES_PER_SESSION` when the session already has 10 enabled rules and the request
would enable another (disable or delete an existing rule before enabling another), `404
SESSION_NOT_FOUND` for an unknown session (all three check, so a typo is never a
silent empty list or a successful delete), `409 CANNOT_SCHEDULE` when the
session is crashed or ended, or the schedule is `idle` on a remote session, and
`503 KEEPALIVE_UNAVAILABLE` when the tool layer is not running, which is not the
same as "no rules".

`INVALID_TOOL_INPUT` is not keep-alive specific: any body the tool schema
rejects comes back as 400 on the session, keep-alive, layout and workspace
endpoints. Resending it unchanged never succeeds, so fix the body instead of
retrying. A 500 `TOOL_CALL_FAILED` is the other case, where the tool itself
broke and a retry can make sense. `/api/terminal/notify` answers a rejected
message with `400 INVALID_NOTIFY_MESSAGE` instead: same status, different code.

## Layout

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/terminal/layout` | Current layout, panes and pane ids. `?full=true` adds the content bindings and geometry |
| `POST` | `/api/terminal/layout` | Set the layout type, optionally placing sessions |
| `POST` | `/api/terminal/layout/panes/:paneId/assign` | Put a session in a pane |
| `POST` | `/api/terminal/layout/panes/:paneId/activate` | Focus a pane |
| `POST` | `/api/terminal/layout/panels/:panelId/activate` | Focus a tab |
| `POST` | `/api/terminal/layout/restore` | Restore a layout snapshot, in the shape `?full=true` returns |

Capture the snapshot you intend to restore with `?full=true`. Restore binds panes
by `contentType` / `contentId`, which the default slim shape does not carry:
posting a slim snapshot still applies the layout with every pane left empty, and
each slim pane comes back under `restored.skipped` with `reason: "SLIM_PANE"`,
so the response signals that nothing was bound. The `termdock layout restore`
subcommand keeps refusing slim files outright.

The slim shape now carries an optional `contentType` field (#2150). A file pane
(`contentType: "file"`) is reported under `restored.skipped` with
`contentType: "file"` and `contentId` set to the pane id, instead of being
silently dropped. Older clients that omit `contentType` continue to work.
A browser pane (`contentType: "browser"`, `contentId` = the browser tab's id)
follows the same rules: skipped as `SLIM_PANE` from a slim snapshot, restored
from a full one while that tab is still open.

## Agent sessions

An AgentSession is a tracked agent run, whether SDK-driven or associated with a
terminal; it is distinct from the terminal session and its PTY.

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/agent-sessions` | Create an SDK agent session |
| `POST` | `/api/agent-sessions/attach` | Attach to an agent already running in a terminal |
| `POST` | `/api/agent-sessions/resolve` | Resolve which agent session belongs to a target |
| `GET` | `/api/agent-sessions` | List live sessions |
| `GET` | `/api/agent-sessions/:id` | Status of one |
| `GET` | `/api/agent-sessions/:id/events` | Event stream (SSE) |
| `GET` | `/api/agent-sessions/:id/rendered` | The rendered conversation view |
| `GET` | `/api/agent-sessions/:id/rendered/stream` | That view as a stream |
| `POST` | `/api/agent-sessions/:id/input` | Send a message |
| `POST` | `/api/agent-sessions/:id/callbacks` | Deliver a structured external event to an existing agent session |
| `POST` | `/api/agent-sessions/:id/interrupt` | Interrupt |
| `POST` | `/api/agent-sessions/:id/restart` | Restart |
| `DELETE` | `/api/agent-sessions/:id` | Kill |
| `POST` | `/api/agent-sessions/hooks` | Where an agent CLI's hook posts permission prompts and questions |

`session.sessionId` is Termdock's identity for one run, not the CLI's conversation id. Two terminals can be reading the same conversation file, and each run still needs its own identity. The conversation file's id is reported separately as `session.metadata.aiSessionId`.

`resolve` returns that conversation id in its `sessionId` field, and `attach` accepts either form. Every other path above addresses a single run, so pass the `sessionId` that create or attach returned. Resolving and then calling `GET /:id` with the resolved id gives you a 404.

### External monitor callbacks

`POST /api/agent-sessions/:id/callbacks` accepts an existing AgentSession id,
its terminal id, or a unique tab name. A shell-only terminal returns
`404 SESSION_NOT_FOUND`; the endpoint never attaches an agent or falls back to
raw PTY input. Ambiguous agent associations return
`409 AGENT_SESSION_CALLBACK_CONFLICT`. Tool Runtime callers use
`agent-session:callback` with the canonical AgentSession `sessionId`.

```json
{
  "source": "handoff-monitor",
  "eventKind": "artifact-changed",
  "dedupeKey": "duo-award-a",
  "message": "Duo 交付有變化，請讀取並核對。",
  "metadata": { "artifact": "/tmp/duo-award-a/REPORT.md" }
}
```

`source`, `eventKind`, and `message` are required. `dedupeKey` and the JSON-object
`metadata` are optional. The top-level object rejects unknown fields. Success
returns `{ "success": true, "data": { "sessionId": "...", "deliveryId": "...", "createdAt": "..." } }`.
Each call gets a new delivery id, even when `dedupeKey` repeats. The receipt
acknowledges the provider send, not completion of the agent's work; it is not a
durable delivery record.

Callbacks share the ordinary per-session send sequence and dispatch cap. An
interactive agent receives the event at its turn-ready boundary, without an
interrupt or answering a permission prompt. Metadata stays structured until
the provider adapter renders a `termdock.agent-callback.v1` envelope. A timeout
can leave delivery uncertain, so reconcile before retrying. Termdock does not
deduplicate, merge, or automatically retry callbacks. `source`, `eventKind`,
`dedupeKey`, and `metadata` are untrusted collaboration data, not authenticated
sender identity; the existing bearer token and `agent-session` scope still
control access. Generic terminal `/input` keeps its existing behavior.

For OpenCode daemon sessions, waiting for the current turn to become idle is
capped at 30 seconds. A still-busy run returns
`409 AGENT_SESSION_CALLBACK_CONFLICT` without failing or interrupting that run;
retry after it becomes idle.

`/rendered` returns the full retained view. `/rendered/stream` frames are each capped
at 56 KiB: when the view is bigger, the frame drops the oldest entries first and
rebuilds `transcript` from what remains, so treat a frame as the newest window and
resync from `/rendered` when you need older history. The server uses drain-based
backpressure detection (#2152): a single large frame does not close the stream.
The stream waits up to 5 s for the socket to drain; if the socket does not drain
within that window, or if more than 4 MiB of serialized frames queue up while waiting,
the server closes the stream as a slow consumer. On disconnect resync from `/rendered`
and reconnect. `/events` applies the same detection; its backlog replay on connect
(`since`) pauses while the socket is backpressured, so a normal reader gets the whole
backlog whatever its size.

Input is dispatched one message at a time per session, capped at 180 seconds.
Failures: `504 AGENT_SESSION_DISPATCH_TIMEOUT` when the provider does not settle
within that cap, which releases the wait without cancelling the work, so the
message may still have reached the agent; and `409 AGENT_SESSION_DISPATCH_BUSY`
when a message that timed out earlier has not settled yet. Do not retry the input
on a loop for either: `409` clears when that run settles, and sending again while
it is in flight puts two turns into the same conversation. A timed-out message
that never settles does not park the session forever either: after 10 minutes
(`staleDispatchTimeoutMs`) with no restart or `DELETE` taking over, Termdock
force-evicts the record. `GET /:id`, input, and `DELETE` answer `404` and
`restart` answers `409 AGENT_SESSION_RESTART_UNAVAILABLE` (cached create input
is gone; use `attach`) for that id afterwards, and the id no longer appears in the list even
when the provider daemon still knows the conversation. The one way back is an
explicit `attach`, which re-adopts the daemon-persisted conversation as a new
lifecycle, and it only succeeds once the abandoned run has settled: while that
run is still in flight, `attach` answers `409 AGENT_SESSION_DISPATCH_BUSY` too,
and the rejection clears on its own when the run settles. If that run never
settles, the id stays unadoptable for the rest of the process lifetime:
create a new session instead of retrying attach. `lifetime.evictsAt` stays `null` during that window, so do not read
`null` as the absence of a deadline; escalate to restart or `DELETE` well
before it.

`restart` is the way out of both, but it is not guaranteed to work on the first
call. It only recreates the session once the abandoned run has settled on its
own, so it answers `409 AGENT_SESSION_DISPATCH_BUSY` while that run is still in
flight, and `504 AGENT_SESSION_PROVIDER_STOP_TIMEOUT` when the stop call itself
does not report back within 30 seconds. `interrupt` and `DELETE` share that 30
second cap and the same `504`, and `DELETE` answers `500` when the provider
cannot reach its daemon. For restart and `interrupt`, nothing was recreated and
the session was left intact, so the operation is safe to repeat. A failed
`DELETE` instead marks the session `failed` with `lastError` and arms the
retention clock (`lifetime.evictsAt` is set); no `killed` lifecycle is
published, input keeps answering `409` while an abandoned run is still blocking,
and repeating the `DELETE` while the record lasts is safe and lifts that block
when it succeeds. A `DELETE` on a session that already settled (`completed`,
`killed`, or `failed` with nothing still in flight) leaves the stored state
alone and publishes no `session.error`: the retention clock stays, or is armed
if it was missing. `409 SESSION_NOT_RUNNING` is only the usual exit there; a
provider error still answers `500` and the stop cap `504`.

## Remote push

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/terminal/notify` | Push a message to the user's Discord/Telegram. See the `termdock-notify` skill |

## Service tokens

| Method | Path | Purpose |
|---|---|---|
| `POST` | `/api/auth/bootstrap-challenge` | Prove the peer is Termdock before sending it the bootstrap secret |
| `POST` | `/api/auth/service-tokens` | Mint a token for a daemon, using the bootstrap secret |
| `POST` | `/api/auth/service-tokens/:id/rotate` | Rotate |
| `DELETE` | `/api/auth/service-tokens/:id` | Revoke |

A loopback port is first-come-first-served, so anything minting a token by hand should send `{"nonce":"<32+ hex chars>"}` to the challenge endpoint first and check that `data.proof` equals `HMAC-SHA256(bootstrapSecret, "<nonce>|<port>")` in hex, using the port it dialed. Any other outcome means do not send the secret. The `termdock` CLI already does this for you.

## Envelope and streams

Success is `{"success":true,"data":{...}}`. Failure is `{"success":false,"error":{"code":"...","message":"..."}}` with a non-2xx status. `401` means the token is missing or wrong.

The CLI prints the unwrapped `data`, not this envelope. `session output --follow --json` converts SSE into event NDJSON. Custom MCP examples retain the raw envelope in text content and map errors to `isError`; built-in Code Graph MCP is a separate eight-tool AST/code surface. HTTP SSE and webhooks do not imply MCP Events support.

Full request and response shapes, including the settings that gate the API, are in `docs/ref/api/TERMINAL-API.md` in the Termdock repository.

## Live Prompt library schedules (1.22.0)

`PUT /api/terminal/sessions/:id/keepalive` accepts
`{"rule":{"id":"review","enabled":true,"schedule":{"kind":"daily","time":"09:00"},"message":"","promptRef":{"slug":"review","scope":"project"}}}`.
The reference is resolved again at each fire using the target workspace. Use
`global` for a global entry; project references require a local target workspace.
Do not combine nonempty `message` and `promptRef`, or schedule prompts containing
variables. Deleted/unreadable/unsupported prompts skip the slot rather than
falling back to stale text. Existing screen and typing interlocks still apply.
The API also accepts `{"kind":"once","atMs":<future epoch milliseconds>}`.

## Local terminal ownership (`persistent-term-*`)

- Local workspace create defaults to broker ownership on desktop, split panes, HTTP, CLI and Tool Runtime. Terminals keep running after App Quit; there is no user-facing persistent mode or special creation entry. Existing live App-owned processes are not migrated.
- `terminal:create` and HTTP create accept `persistence?: "app" | "broker"`: omitted means automatic broker with silent App-owned fallback; `app` explicitly selects App-owned lifetime; `broker` requires the broker and reports failure rather than falling back. No new CLI flag is added.
- Capability unavailable, blocked Windows Job, broker unreachable/incompatible or unsupported exact launch options fall back before a native effect. Custom env/cwd/shell, persisted logs and dimensions unsupported by an older broker retain the App-owned capability. Unknown sent-create outcomes never open a second shell. Remote/peer/SSH workspaces retain their remote owner.
- The default create pipeline grants this Main the writer. Input/submit/key/interrupt/resize require that grant and fence stale queued calls; they never take over another client implicitly. Without a valid lease a write returns 409 `STALE_ATTACHMENT`, and rejected input is not retried. Keep-alive and submissions share the ordinary submit chain; `queueUntilReady` and agent submissions use existing readiness logic. CLI `session attach` remains the SSE/stdin bridge, not a broker writer grant.
- Output uses the same bounded Main projection for renderer and agent reads: `raw` retains ANSI rows; `text`/`content` use App-owned normalization and chrome filtering. Numeric `cursor`/`nextCursor` are App-style line cursors: pass `nextCursor` to `--since` or SSE `since` for the next read. Clear, attachment rebuild or an expired history window returns `truncated:true`; resume from the returned cursor. `snapshotCursor` remains the separate broker source cursor. Follow/SSE and `wait-output` require this Main's attachment and end with `output.error` on takeover/detach (`STALE_ATTACHMENT`), broker disconnect (`BROKER_UNREACHABLE`) or session end (`SESSION_ENDED`). CLI follow writes that event in JSON mode and exits nonzero. Reads do not acquire or steal a writer; unowned sessions retain read-only snapshots, which may rebuild the line projection and mark old cursors truncated. `screen` still uses the shared headless projection and hash/window rules, with no incremental cursor semantics; `source=dom` remains unsupported. The default window is 50 lines; `ifHash` remains available.
- Names resolve through the ordinary terminal name namespace. Unified protocol v1.1 supports authoritative writer-fenced rename, names up to 200 characters, shell process evidence, dimensions 500×100 and optional bounded error hints. Only v1.1/v1.0 are negotiated. v1.0 has no name/rename/process-evidence/error-message extensions and retains 240×100; new fields are stripped from old-client replies/events/deduplicated results. v1.1-only sessions require a compatible client; old broker rename returns `RENAME_UNSUPPORTED`.
- Closing a desktop tab or `session destroy` terminates its shell and children and waits for process-tree acknowledgement. Quit/Cmd+R and explicit `terminal:detach` do not terminate them. There is no session-count cap. The broker warns at 128 MiB RSS and refuses new creation at 256 MiB (`RESOURCE_LIMIT`), without terminating existing work. PTY/process exhaustion returns `RESOURCE_LIMIT` with a readable recovery hint from a v1.1 broker; other spawn failures return `CAPABILITY_UNAVAILABLE`.
- Startup uses the one savedSessions/layout: living processes reconnect in their original pane/order; confirmed ended/missing processes rebuild with a NEW ID, saved history and keep-alive rules. Unreachable/incompatible broker panes stay in place for retry; other writers remain read-only until confirmed takeover. Manual `terminal:restore-persistent {sessionId}` is Tool Runtime only (no HTTP/CLI route), returns `{snapshot, broker, session?, errorCode?}` and does not accept caller cwd/shell or replay uncertain create. Existing App-owned snapshots retain snapshot-only restore.
- Read-only `terminal:quit-summary {}` returns App-ending/background-running counts; a broker count of `null` is unknown, not zero. Broker mutations are never automatically retried. `name` is broker-held metadata; `paneId`/`stealFocus` use ordinary desktop placement, and `background:true` cannot be combined with placement.
