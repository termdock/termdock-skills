---
name: termdock-notify
displayName: Termdock Notify
description: Pushes a message to the user's phone (Discord/Telegram) from a Termdock terminal. Use when you finish work the user is waiting on, when you are blocked and need their decision, or when something changed that invalidates the plan they approved. Skip when the user is clearly at the keyboard, and never for progress narration.
version: 3
minAppVersion: 1.20.0
---

# Notify The User Away From The Keyboard

Termdock relays your message to the remote the user has configured. Use it when
the useful information exists **now** and waiting for them to look at the screen
costs them something.

When both Discord and Telegram are connected, your push goes to Discord only:
your message belongs to one session, and Discord is the one that can put it in
that session's thread where the user can answer it. Telegram still carries the
things the user subscribes to explicitly, such as `/watch`.

```bash
termdock notify "migration finished, 412 rows moved. Want me to drop the old table?"
```

That is the whole interface. The message carries the name of the terminal tab it
came from, so the user can tell your session apart from the others they have
running. No session id, no token, no setup.

On Discord, each session gets its own thread under the user's channel, and your
pushes land in it. Name that thread yourself: pass `--title` on your **first**
push with a short description of the task, so the user sees "fix attach
ambiguity" instead of a tab name.

```bash
termdock notify "taking over the attach fix, starting with the provider" --title "fix attach ambiguity"
```

`--title` only takes effect on the push that creates the thread; later pushes
ignore it. Without it the thread falls back to the tab name. Telegram has no
threads and ignores the flag.

## When To Send

Send when one of these is true:

- **The work they asked for is done** and they are not watching. One line saying
  what happened, plus anything they must decide next.
- **You are blocked on their decision.** State the choice and the options. Do not
  send "I have a question" without the question.
- **Something invalidated the plan they approved**: a failing assumption, a
  missing dependency, a destructive step you will not take without a yes.
- **A long job finished** (build, migration, test suite) and the result changes
  what they would do next.

## When Not To Send

- **Progress narration.** "Starting step 3" is noise on a phone.
- **Anything they can already see.** If they typed a command a moment ago and the
  output is on screen, they are at the keyboard.
- **Retrying after a failure.** A rejected send is never a transient error.
- **Splitting one thought into several messages.** Send once, completely.

## Answer In The Same Channel They Asked From

On Discord, anything the user types in your session's thread is delivered to
your terminal as input, no `/attach` needed. On Telegram, a reply only reaches a
terminal when the user has run `/attach` on it, and only one session can be
attached at a time.

**Nothing of yours goes back on its own.** Someone asking from the thread is
sitting in front of a phone, so an answer you only print is an answer they never
see. When a message arrives from the remote, push your answer with `notify` once
you have it. Same rule for a decision you asked for: they told you which way to
go, so tell them when it is done.

Push one message, complete, the way you would say it out loud. The working
output stays in the terminal for when they get back.

A question you push is still a question you may never hear back on. Leave it in
your terminal too, and carry on as if the push had not happened.

## When The Send Fails

A non-zero exit code means **the message did not reach them**. Do not retry in a
loop: none of the reasons are transient. Stop sending, carry on with the work,
and leave what you wanted to say in the terminal.

Reasons and exit codes: `references/cli.md`. The HTTP surface for callers that
cannot run the CLI: `references/api.md`.
