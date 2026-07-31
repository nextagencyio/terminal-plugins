# ghostty-badges

Emoji state badges in Ghostty tab titles for AI agent CLIs (Claude Code, Devin CLI).

Ghostty has no per-tab badge API, but tab titles follow OSC 0/2 escapes. The
`bin/ghostty-badge` script sets the title to `<emoji> <Agent> — <project>`:

| State | Icon | Meaning |
|---|---|---|
| `working` | 🔄 | Agent is running |
| `attention` | 🔔 | Needs permission / input |
| `question` | ❓ | Asked the user a question |
| `done` | ✅ | Finished, waiting on you |
| `error` | ❌ | Failed |
| `clear` | — | Reset title |

It writes straight to `/dev/tty` (hook stdout is captured by the calling CLI)
and is a **silent no-op outside Ghostty** (`TERM_PROGRAM`/`GHOSTTY_RESOURCES_DIR`
guard), so it's safe in configs shared across terminals.

## Install

**Devin CLI** — idempotent merge into `~/.config/devin/config.json`:

```sh
./install-devin.sh
```

**Claude Code** — add hooks to `~/.claude/settings.json` (personal settings;
pair `Notification` with a chime if you like):

| Event | State |
|---|---|
| `UserPromptSubmit`, `PostToolUse` | `working` |
| `Notification` | `attention` |
| `Stop` | `done` |
| `SessionEnd` | `clear` |

Each hook command: `"$HOME/.local/bin/ghostty-badge" Claude <state>`

## Notes

- Claude Code sets its own tab title (session topic), so it may occasionally
  replace the badge until the next state change.
- Ghostty's built-in bell `title` feature (🔔 prefix, auto-clears on refocus)
  works independently and complements this.
- Pairs well with Claude Code's `terminalProgressBarEnabled: true` — Ghostty
  renders OSC 9;4 progress natively (`progress-style = true` default).
