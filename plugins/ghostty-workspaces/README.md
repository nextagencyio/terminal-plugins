# ghostty-workspaces

Named project workspaces for Ghostty on macOS — `workspace horizon` opens your
project windows in one shot. Fills the gap left by Warp/Wave-style workspaces:
Ghostty has no profiles, saved layouts, or session manager by design.

```
workspace                              # list defined workspaces
workspace <name>                       # open all windows for <name>
workspace <path> [command...]          # ad-hoc window at a directory
workspace add <name> <dir> [command]   # define an entry
workspace edit                         # edit the config
```

Config lives at `~/.config/terminal-plugins/workspaces.conf` (personal, never
committed) — `name|dir|command` lines, command optional. A name may appear on
multiple lines; each opens its own window, so a workspace can be
"Claude window + shell window" or one window per repo:

```
horizon|~/Sites/horizon-web|claude
horizon|~/Sites/horizon-api|
```

## How it works / caveats

- macOS Ghostty can only open a window at a directory from the CLI via
  `open -na Ghostty.app --args --working-directory=...` (`+new-window` is
  GTK-only), so **each window is its own Ghostty instance**. They look
  and behave identically; the visible difference is cmd+` won't cycle between
  them (use cmd+tab) and each quits independently.
- On Linux, `ghostty +new-window` is used instead (single instance, D-Bus).
  Requires Ghostty >= 1.3, which added `--working-directory`/`-e` to
  `+new-window`. See the repo's UBUNTU.md.
- Commands run as `zsh -ic '<cmd>; exec zsh -i'` so the window drops to a
  shell when the command exits instead of closing.
- Pairs with `window-save-state = always` in Ghostty config: your arranged
  windows/tabs/splits come back after a quit. For detachable, layout-defined
  sessions inside a single window, use tmux or zellij instead.
- Env overrides: `WORKSPACE_CONF`, `GHOSTTY_APP`.

Install: symlink `bin/workspace` into `~/.local/bin`.
