# NextAgency Terminal Plugins

Custom Claude Code plugin marketplace for [nextagencyio](https://github.com/nextagencyio) — terminal integrations for AI agent CLIs.

> Renamed from `wave-plugins` (2026-07-31) after moving off Wave Terminal; the Wave plugins remain for reference. GitHub redirects the old repo URL.

```
/plugin marketplace add nextagencyio/terminal-plugins
```

## Plugins

Also installable as a Devin CLI plugin: `devin plugins install nextagencyio/terminal-plugins`

| Plugin | Terminal | Description |
|---|---|---|
| [ghostty-badges](plugins/ghostty-badges) | Ghostty | Emoji agent-status badges in tab titles via OSC 0 (Claude Code, Devin CLI) |
| [wave-badges](plugins/wave-badges) | Wave | Agent status badges, contextual notifications + block titles (Claude Code, Devin CLI, opencode) |
| [tab-font-patch](plugins/tab-font-patch) | Wave | Enlarge Wave's tab-bar font (no built-in setting exists) by patching `app.asar`, with auto-reapply after Wave updates |
