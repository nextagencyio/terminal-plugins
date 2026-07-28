# wave-badges

Agent status badges, contextual notifications, and block titles for [Wave Terminal](https://www.waveterm.dev/). Run multiple AI agents in parallel and see at a glance which are working, which are done, and which are waiting on you — Warp-style agent indicators, but for any agent CLI with lifecycle hooks.

| State | Badge | Extras |
|---|---|---|
| Session start | — | block title set to `Agent — project · branch` |
| Working | animated cyan spinner, priority 5 | re-asserted on every tool call |
| Needs permission | yellow bell, priority 20 | beep + notification naming the tool and project |
| Asking a question | gold question mark, priority 20 | beep + notification |
| Done | green check, priority 10 | notification with project name |
| Error (turn failed) | red triangle, priority 15 | notification |

Badges are **pid-linked** to the agent process, so they survive Wave's clear-on-focus and disappear automatically when the session exits. Notifications include the project folder (from the hook payload's `cwd`), so with five agents running you know which one pinged you without looking.

## Requirements

- Wave Terminal ≥ 0.14.2 (`wsh badge` support)
- `jq` (for payload context; degrades gracefully without it)
- macOS: notifications allowed for Wave (fires on first `wsh notify`; check Focus/DND if banners don't appear)
- Linux: `wsh` on `PATH`, or Wave installed at `/opt/Wave` (`.deb`/`.rpm`) or `~/Applications/wave-terminal` (extracted AppImage) so the bundled `wsh` can be found

## Install — Claude Code

```
/plugin marketplace add nextagencyio/wave-plugins
/plugin install wave-badges@nextagencyio
```

Hooks ship with the plugin; no settings.json editing needed. Restart sessions to activate.

## Install — Devin CLI

```
devin plugins install nextagencyio/wave-plugins
```

then run the `/wave-plugins:wave-badges-setup` skill, or from a clone of this repo:

```
./plugins/wave-badges/install-devin.sh
```

Symlinks the badge script to `~/.local/bin/wave-badge` and merges hook entries into `~/.config/devin/config.json` (idempotent).

## Install — opencode

From a clone of this repo:

```
./plugins/wave-badges/install-opencode.sh
```

Symlinks a plugin into `~/.config/opencode/plugins/` that maps opencode events (`session.idle`, `permission.asked`, `session.error`, tool execution) onto the same badge states.

## Other agents

Any tool that can run a shell command on lifecycle events can join:

```
echo "$HOOK_JSON" | wave-badge '<Agent Name>' <start|working|attention|question|done|error|clear>
```

The JSON payload is optional (`cwd`, `message`, `tool_name` are used when present). The script is a no-op outside Wave, so it's safe in configs shared across terminals.

## How it works

- `wsh badge` / `wsh notify` / `wsh setmeta frame:title=…` talk to Wave from inside a block
- Wave only replaces a badge with a higher-priority one, so the script clears before every set to make state transitions (bell → spinner → check) land
- Wave's focus auto-clear skips pid-linked badges — the script walks the process tree to find the agent process (`claude`/`devin`/`opencode`/`node`/`bun`) and links badges to it
- Block titles use the `frame:title` block metadata (tab names have no `wsh` API)
