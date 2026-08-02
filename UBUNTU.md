# Ubuntu setup

Reproducing the Ghostty + agent-CLI setup from this repo on Ubuntu. Everything
in the repo is cross-platform; this is the checklist of what differs from macOS.

## 1. Install Ghostty (>= 1.3)

Ubuntu has no official Ghostty package. Options, in order of preference:

```sh
sudo snap install ghostty --classic          # community snap, kept current
```

or the [ghostty-ubuntu](https://github.com/mkasberg/ghostty-ubuntu) .deb
releases, or build from source per https://ghostty.org/docs/install/build.
Verify: `ghostty +version` — **1.3+ is required** for
`+new-window --working-directory/-e`, which the `workspace` launcher uses.

Optional systemd/D-Bus integration makes `+new-window` fast and lets it
auto-start Ghostty: https://ghostty.org/docs/linux/systemd

## 2. Clone + symlink

```sh
gh repo clone nextagencyio/terminal-plugins ~/nextagencyio/terminal-plugins
mkdir -p ~/.local/bin   # already on PATH in Ubuntu's default ~/.profile
cd ~/nextagencyio/terminal-plugins/plugins
ln -sf "$PWD/ghostty-badges/bin/ghostty-badge"    ~/.local/bin/ghostty-badge
ln -sf "$PWD/ghostty-workspaces/bin/workspace"    ~/.local/bin/workspace
ln -sf "$PWD/agent-chime/bin/agent-chime"         ~/.local/bin/agent-chime
```

## 3. Ghostty config (`~/.config/ghostty/config`)

Config and GTK tab bar CSS are tracked in `plugins/ghostty-config/`. Install:

```sh
./plugins/ghostty-config/install.sh   # symlinks config + ghostty-custom.css into ~/.config/ghostty/
```

The CSS styles the tab bar to match the Ayu dark theme with a blue active tab.
Edit `plugins/ghostty-config/ghostty-custom.css` to change tab colors.

Do NOT bother with `window-save-state = always` — it rides macOS state
restoration and does nothing on GTK. On Ubuntu, `workspace <name>` (or
tmux/zellij) is the session-persistence story.

## 4. Agent CLI hooks

Identical to macOS — the scripts self-adapt:

- **ghostty-badge**: no changes; same env guard, same OSC 0 titles.
- **agent-chime**: auto-detects Linux and uses `paplay` with the freedesktop
  "complete" sound (`sudo apt install sound-theme-freedesktop` if missing),
  falling back to `canberra-gtk-play`, then the terminal bell.
- **Devin**: `./plugins/wave-badges/install-devin.sh` then
  `./plugins/ghostty-badges/install-devin.sh` (both idempotent).
- **Claude Code** `~/.claude/settings.json` — same as macOS:
  `"preferredNotifChannel": "auto"`, `"terminalProgressBarEnabled": true`,
  hooks calling `"$HOME/.local/bin/ghostty-badge" Claude <state>`
  (UserPromptSubmit/PostToolUse→working, Notification→attention + agent-chime,
  Stop→done, SessionEnd→clear).

## 5. Notifications

OSC 9/777 from Claude Code flow through Ghostty to the desktop notification
daemon — nothing to configure on GNOME. Bell `attention`/`title` features
behave per-desktop (GNOME: notification; KDE: taskbar highlight).

## 6. Workspaces

`workspace` detects Linux and uses `ghostty +new-window` — windows open in the
**same instance** (nicer than macOS, where each window is its own instance).
Config format is identical; copy `~/.config/terminal-plugins/workspaces.conf`
between machines, adjusting paths.
