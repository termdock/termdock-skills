# HTTP API reference

For callers that cannot run the CLI. The CLI is a thin wrapper over these.

Base URL is `http://127.0.0.1:<port>`; get the port from `termdock hostinfo --json`. Every request needs `Authorization: Bearer <token>`.

```bash
curl -s -H "Authorization: Bearer $TERMINAL_API_TOKEN" \
  http://127.0.0.1:3036/api/terminal/sessions
```

## Terminal sessions

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/terminal/workspaces` | Workspaces, and their ids for creating sessions |
| `POST` | `/api/terminal/sessions` | Create. Body takes `workspaceId`, `name`, `background` |
| `GET` | `/api/terminal/sessions` | List. `?workspaceId=` filters |
| `GET` | `/api/terminal/sessions/:id/status` | Activity, whether it is waiting at a prompt |
| `GET` | `/api/terminal/sessions/:id/output` | Read. `?mode=raw\|text\|content\|screen`, `?lines=`, `?since=` |
| `GET` | `/api/terminal/sessions/:id/events` | Same content as an SSE stream |
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

## Agent sessions

Separate from terminal sessions: these are SDK-driven agent conversations, not PTYs.

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
| `POST` | `/api/agent-sessions/:id/interrupt` | Interrupt |
| `POST` | `/api/agent-sessions/:id/restart` | Restart |
| `DELETE` | `/api/agent-sessions/:id` | Kill |
| `POST` | `/api/agent-sessions/hooks` | Where an agent CLI's hook posts permission prompts and questions |

`session.sessionId` is Termdock's identity for one run, not the CLI's conversation id. Two terminals can be reading the same conversation file, and each run still needs its own identity. The conversation file's id is reported separately as `session.metadata.aiSessionId`.

`resolve` returns that conversation id in its `sessionId` field, and `attach` accepts either form. Every other path above addresses a single run, so pass the `sessionId` that create or attach returned. Resolving and then calling `GET /:id` with the resolved id gives you a 404.

`/rendered` returns the full retained view. `/rendered/stream` frames are each capped
at 56 KiB: when the view is bigger, the frame drops the oldest entries first and
rebuilds `transcript` from what remains, so treat a frame as the newest window and
resync from `/rendered` when you need older history. The cap is not a liveness
guarantee: consecutive updates can still close the stream as a slow consumer, so
on disconnect resync from `/rendered` and reconnect.

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

## Envelope

Success is `{"success":true,"data":{...}}`. Failure is `{"success":false,"error":{"code":"...","message":"..."}}` with a non-2xx status. `401` means the token is missing or wrong.

Full request and response shapes, including the settings that gate the API, are in `docs/ref/api/TERMINAL-API.md` in the Termdock repository.
