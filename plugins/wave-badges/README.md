# wave-badges

Agent status badges and desktop notifications for [Wave Terminal](https://www.waveterm.dev/) tabs. Run multiple AI agents in parallel and see at a glance which are working, which are done, and which are waiting on you — Warp-style agent indicators, but for any agent CLI with lifecycle hooks.

| State | Badge | Extras |
|---|---|---|
| Working | animated cyan spinner (`spinner-third+spin`) | re-asserted after every tool call |
| Needs input | yellow bell, priority 20 | system beep + desktop notification |
| Done | green check, priority 10 | desktop notification |

Badges are **pid-linked** to the agent process, so they survive Wave's clear-on-focus and disappear automatically when the session exits. The check stays until you give the agent something new to do.

## Requirements

- Wave Terminal ≥ 0.14.2 (`wsh badge` support)
- macOS notifications allowed for Wave (fires on first `wsh notify`; check Focus/DND if banners don't appear)

## Install — Claude Code

```
/plugin marketplace add nextagencyio/claude-plugins
/plugin install wave-badges@nextagencyio
```

Hooks ship with the plugin; no settings.json editing needed. Restart sessions to activate.

## Install — Devin CLI

From a clone of this repo:

```
./plugins/wave-badges/install-devin.sh
```

Symlinks the badge script to `~/.local/bin/wave-badge` and merges hook entries into `~/.config/devin/config.json` (idempotent).

## Other agents

Any tool that can run a shell command on lifecycle events can join:

```
wave-badge '<Agent Name>' <working|attention|done|clear>
```

The script is a no-op outside Wave, so it's safe in configs shared across terminals.

## How it works

- `wsh badge` / `wsh notify` talk to Wave from inside a block
- Wave only replaces a badge with a higher-priority one, so the script clears before every set to make state transitions (bell → spinner → check) land
- Wave's focus auto-clear skips pid-linked badges — the script walks the process tree to find the agent process (`claude`/`devin`/`node`/`bun`) and links badges to it
