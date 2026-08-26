# Termdock Skills

Agent skills for [Termdock](https://github.com/termdock/termdock-issues), the AI-native terminal. A skill teaches your coding agent one Termdock capability: what it does, when to reach for it, and when not to.

Termdock ships these skills and installs them for you. This repository exists so they can be updated without waiting for an app release, and so you can install them yourself if you would rather not let the app write to your skills directory.

## What is here

| Skill | What it teaches |
|---|---|
| `termdock-notify` | Push a message to your phone (Discord/Telegram) from a terminal, so an agent can tell you it finished or needs a decision while you are away |
| `termdock-ast` | Query the AST index: where a symbol lives, who calls it, what breaks if it changes |

Each skill is a directory under `skills/` containing a `SKILL.md` and, where the detail does not belong in the main file, a `references/` folder.

## Install

Clone and run the installer:

```bash
git clone https://github.com/termdock/termdock-skills.git
cd termdock-skills
./install.sh
```

By default it installs every skill for every agent it finds (`~/.claude/skills`, `~/.codex/skills`, `~/.gemini/skills`). It never touches an agent directory that does not already exist.

```bash
./install.sh --dry-run                 # show what would happen, change nothing
./install.sh --skill termdock-notify   # one skill
./install.sh --platform claude         # one agent
./install.sh --force                   # overwrite local edits
```

Without `--force`, a skill you have edited locally is left alone and reported, so your changes are never silently overwritten.

## Versions

Version lives in each `SKILL.md` front matter, not in a separate manifest. Two files would drift; the skill file has to be read anyway.

```yaml
---
name: termdock-notify
version: 1
minAppVersion: 1.20.0
---
```

- `version` increments whenever the content changes in a way that matters to an agent following it.
- `minAppVersion` is the oldest Termdock that has the capability the skill describes. A skill teaching a command your app does not have is worse than no skill, so the installer and Termdock both skip it. **Absent means no constraint.**

## Contributing

Open an issue first. A skill is instructions an agent will follow without checking, so changes are reviewed for whether the advice is still true of the shipped app, not just for whether it reads well.

Two things that keep these useful:

- **Say when not to use it.** An agent with a hammer needs to know what is not a nail. Every skill here has a "when not to" section and it is the part that gets read most.
- **Do not document what the app does not do yet.** Bump `minAppVersion` in the same change that starts describing a new capability.
