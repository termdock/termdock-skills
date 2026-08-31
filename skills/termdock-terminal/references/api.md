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

## Layout

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/api/terminal/layout` | Current layout, panes and pane ids |
| `POST` | `/api/terminal/layout` | Set the layout type, optionally placing sessions |
| `POST` | `/api/terminal/layout/panes/:paneId/assign` | Put a session in a pane |
| `POST` | `/api/terminal/layout/panes/:paneId/activate` | Focus a pane |
| `POST` | `/api/terminal/layout/panels/:panelId/activate` | Focus a tab |
| `POST` | `/api/terminal/layout/restore` | Restore a layout snapshot |

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
