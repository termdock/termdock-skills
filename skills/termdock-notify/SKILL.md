---
name: termdock-notify
description: Pushes a message to the user's phone (Discord/Telegram) from a Termdock terminal. Use when you finish work the user is waiting on, when you are blocked and need their decision, or when something changed that invalidates the plan they approved. Skip when the user is clearly at the keyboard, and never for progress narration.
version: 1
minAppVersion: 1.20.0
---

# Notify The User Away From The Keyboard

Termdock relays messages to whatever remote the user has configured. Use it when
the useful information exists **now** and waiting for them to look at the screen
costs them something.

```bash
termdock notify "migration finished, 412 rows moved. Want me to drop the old table?"
```

That is the whole interface. The message carries the name of the terminal tab it
came from, so the user can tell your session apart from the others they have
running. No session id, no token, no setup.

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

## Do Not Count On A Reply

A reply only reaches a terminal when the user has run `/attach` on it from their
remote, and only one session can be attached at a time. If they are attached
elsewhere, or not attached at all, their answer goes to another terminal or
nowhere.

So a question you push is a question you may never hear back on. Leave it in your
terminal too, and carry on as if the push had not happened.

## When The Send Fails

A non-zero exit code means **the message did not reach them**. Do not retry in a
loop: none of the reasons are transient. Stop sending, carry on with the work,
and leave what you wanted to say in the terminal.

Reasons and exit codes: `references/cli.md`. The HTTP surface for callers that
cannot run the CLI: `references/api.md`.
