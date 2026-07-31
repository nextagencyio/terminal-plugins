# AGENTS.md

Working notes for AI agents (and future humans) contributing to this repo. Everything done for this setup — even one-off machine config — gets recorded here or committed as code. If you change the environment, update this file in the same commit.

## Repo purpose

Terminal integrations for AI agent CLIs. **Renamed from `wave-plugins` to `terminal-plugins` on 2026-07-31** — Jay moved off Wave Terminal to Ghostty; Wave plugins are kept for reference, active work targets Ghostty. GitHub redirects the old repo URL, but new references should use `nextagencyio/terminal-plugins`. Canonical local clone: `~/nextagencyio/terminal-plugins` (repo-local git identity + credential helper are set there).

Published three ways from one repo:

- **Claude Code plugin marketplace** — `.claude-plugin/marketplace.json` at root, plugin at `plugins/wave-badges/` (hooks auto-load from `hooks/hooks.json`; do NOT add a `"hooks"` key to `plugin.json` — Claude Code treats it as a duplicate and the plugin fails to load; see commit 6807b60)
- **Devin CLI plugin** — `.devin-plugin/plugin.json` + `skills/` at root (Devin plugins are skill bundles only; actual hook wiring is done by `plugins/wave-badges/install-devin.sh`)
- **opencode plugin** — `plugins/wave-badges/opencode/wave-badge.js`, symlinked by `install-opencode.sh`

## Conventions

- Commits and pushes are attributed to **nextagencyio** (`jrcallicott@gmail.com`), never a work account. The local clone has repo-local `user.name`/`user.email` and a credential helper that shells to `gh auth token -u nextagencyio`.
- The canonical badge script is `plugins/wave-badges/bin/wave-badge`; `~/.local/bin/wave-badge` is a symlink to it, so Devin and opencode pick up edits immediately. Claude Code installs the plugin from GitHub, so it only sees **pushed** changes after a session restart or `/plugin` update.
- The script must stay a silent no-op outside Wave (`$WAVETERM_BLOCKID` guard, `exit 0` everywhere) — it lives in configs shared across terminals.
- Wave badge invariants (learned from Wave source): FontAwesome icons only (`+spin/+beat/+fade` suffixes); Wave never replaces a badge with a lower-priority one, so always clear-before-set; focus auto-clear skips pid-linked badges (`--pid`), which is how badges persist until session exit. **Clear-then-set race condition** (2026-07-29): `wsh badge --clear` and the immediately following `wsh badge set` are separate RPC calls whose frontend events can arrive out of order (clear event after set event), silently wiping the new badge — the spinner disappears even though `wsh badge` reports "badge set". A `sleep 0.15` between clear and set fixes it; the delay is imperceptible in practice. This was the root cause of the "waiting icon not showing" bug.
- Personal machine preferences (browser choice, paths) never get hardcoded into shared scripts — use env vars or gitignored local config.

## Machine setup log (Jay's Mac)

Environment changes made alongside this repo, so they can be reproduced on another machine:

### Wave Terminal
- Installed via `brew install --cask wave --appdir=~/Applications` (no sudo for /Applications)
- macOS only registers Wave under Settings → Notifications after the first `wsh notify`; check Focus/DND if banners don't appear

### Agent hook wiring
- Claude Code: `/plugin marketplace add nextagencyio/wave-plugins` + `/plugin install wave-badges@nextagencyio`
- Devin CLI: `devin plugins install nextagencyio/wave-plugins`, then `./plugins/wave-badges/install-devin.sh` (idempotent jq merge into `~/.config/devin/config.json`; leaves Devin's separate `warp-scripts/` integration alone)
- opencode: `./plugins/wave-badges/install-opencode.sh`

### Ghostty badges + progress (2026-07-31)
Wave replacement: Ghostty (1.3.1, `~/Applications/Ghostty.app`). Ghostty has no per-tab badge API and macOS tabs are native/top-only (`gtk-tabs-location` is Linux-only), so agent status goes through **tab titles** instead:

- `plugins/ghostty-badges/bin/ghostty-badge '<Agent>' <working|attention|question|done|error|clear>` sets the title to `<emoji> <Agent> — <project>` via OSC 0, written to `/dev/tty` (hook stdout is captured by the calling CLI). Guards on `TERM_PROGRAM=ghostty`/`GHOSTTY_RESOURCES_DIR` — silent no-op elsewhere, same convention as wave-badge. `~/.local/bin/ghostty-badge` symlinks to it.
- Devin: `plugins/ghostty-badges/install-devin.sh` (idempotent, coexists with the wave-badge entries, which are no-ops outside Wave).
- Claude Code: hooks live in personal `~/.claude/settings.json` (UserPromptSubmit/PostToolUse→working, Notification→attention, Stop→done, SessionEnd→clear) — kept personal rather than shipped as a marketplace plugin for now.
- Claude Code also has `"terminalProgressBarEnabled": true` → OSC 9;4 progress bars, rendered natively by Ghostty (`progress-style = true` default).
- Free extra: Ghostty's default `bell-features` include `title` (🔔 prefix on bell while unfocused, auto-clears) and `attention` (dock bounce).

### Ubuntu portability (2026-07-31)
Jay plans to run this setup on Ubuntu too — `UBUNTU.md` at repo root is the setup checklist. Cross-platform changes:

- `plugins/agent-chime/bin/agent-chime` replaces inline `afplay` everywhere (macOS afplay / Linux paplay→canberra→bell; always exits 0, plays in background). Jay's Claude `Notification` hook and the Devin installer now call it via `~/.local/bin/agent-chime`.
- `workspace` branches on `uname`: macOS `open -na`, Linux `ghostty +new-window --working-directory [-e ...]` (needs Ghostty >= 1.3 — release notes: "GTK: The +new-window CLI command now accepts -e and --working-directory"). Shell wrapper uses `$SHELL` (override `WORKSPACE_SHELL`), not hardcoded zsh.
- Platform facts: `window-save-state` is macOS-only (rides macOS state restoration; no GTK equivalent). Ubuntu install: community snap `snap install ghostty --classic` or mkasberg/ghostty-ubuntu .deb — no official package.

### Ghostty workspaces + window state (2026-07-31)
- `~/.config/ghostty/config` created with `window-save-state = always` — restores windows/tabs/splits/cwds across quits (validated with `ghostty +validate-config`). Running instances need a config reload or relaunch to pick it up.
- `plugins/ghostty-workspaces/bin/workspace` (symlinked at `~/.local/bin/workspace`, which is on PATH): named project workspaces — see the plugin README. Personal workspace definitions live in `~/.config/terminal-plugins/workspaces.conf` (gitignored-by-location, per the no-hardcoded-personal-paths convention).
- Platform facts: `ghostty +new-window` is Linux/D-Bus only; on macOS the only CLI route is `open -na Ghostty.app --args --working-directory=...`, which spawns one instance per window. `-e` forces `quit-after-last-window-closed` and skips shell-integration injection, hence the `zsh -ic '<cmd>; exec zsh -i'` wrapper.

### Attention chime (2026-07-31)
Audible alert when an agent needs attention, alongside the visual badge:

- **Devin CLI**: `install-devin.sh` now also wires `afplay /System/Library/Sounds/Glass.aiff` into the `PermissionRequest` hook (idempotent, same strip/re-add pattern as the badge entries). Override the sound with `WAVE_BADGE_CHIME=/path/to/sound.aiff`, or `WAVE_BADGE_CHIME=none` to skip.
- **Claude Code** (personal settings, not the plugin — sound choice is a machine preference): `~/.claude/settings.json` has `"preferredNotifChannel": "auto"` (OSC 9/777 desktop notifications, works in Ghostty/Wave) plus an async `Notification` hook running the same `afplay` command.


### Shell QoL — macOS/zsh (2026-07-27)
Warp-style input experience at the shell level (works in Wave and any terminal):

```sh
brew install zsh-autosuggestions fzf zsh-syntax-highlighting
```

Appended to `~/.zshrc` (syntax highlighting must be sourced last):

```zsh
# Shell QoL (brew: zsh-autosuggestions, fzf, zsh-syntax-highlighting)
source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source <(fzf --zsh)
# syntax highlighting must be sourced last
source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
```

Gives inline ghost-text history suggestions (→ to accept), fuzzy Ctrl-R history search, and live command syntax highlighting. Considered but not installed: `inshellisense` (IDE-style dropdown completions) — add here if adopted.

### Shell QoL — Linux/bash (2026-07-29)
Same Warp-style input experience on Linux/bash, using [ble.sh](https://github.com/akinomyoga/ble.sh) (Bash Line Editor) + fzf. ble.sh is a single project that covers both zsh-autosuggestions (inline ghost-text) AND zsh-syntax-highlighting (live syntax highlighting) for bash — it replaces GNU Readline entirely. fzf adds fuzzy Ctrl-R history search and fuzzy Tab completion. No sudo needed — both install to `~/.local`.

```sh
# fzf: download prebuilt binary (no sudo)
ver=$(curl -fsSL https://api.github.com/repos/junegunn/fzf/releases/latest | grep -m1 tag_name | cut -d\" -f4)
curl -fsSL -o /tmp/fzf.tar.gz "https://github.com/junegunn/fzf/releases/download/${ver}/fzf-${ver#v}-linux_amd64.tar.gz"
tar xzf /tmp/fzf.tar.gz -C /tmp && install -Dm755 /tmp/fzf ~/.local/bin/fzf

# ble.sh: nightly prebuilt tarball (no build step, no gawk needed)
curl -fsSL https://github.com/akinomyoga/ble.sh/releases/download/nightly/ble-nightly.tar.xz | tar xJf - -C /tmp
bash /tmp/ble-nightly/ble.sh --install ~/.local/share
```

Appended to `~/.bashrc` — ble.sh uses a `--noattach`/`ble-attach` split: source early so it initializes, attach at the end so it takes over readline only after aliases/prompt are set. fzf integration uses `ble-import -d` (delayed load — fzf settings load in background after the prompt is shown, so startup stays fast). Both must be inside the interactive guard (`case $- in *i*) ;; *) return;; esac`):

```bash
# After the interactive guard, early in .bashrc:
source -- ~/.local/share/blesh/ble.sh --noattach

# ... rest of .bashrc (aliases, prompt, etc.) ...

# Near the end, before any exec-based autostart:
ble-import -d integration/fzf-completion
ble-import -d integration/fzf-key-bindings
[[ ${BLE_VERSION-} ]] && ble-attach
```

Key invariants learned: ble.sh requires a real TTY for both stdin AND stdout — it bails with "not intended to be used with --noediting" if stdin isn't a terminal, and silently fails to load if stdout is redirected to a file. This makes it impossible to test from a non-PTY shell (e.g. `bash -c`, devin's exec tool); use `script -qfc 'bash -i'` or a real terminal. ble.sh must be sourced during initial bash startup (natural `.bashrc` load), not re-sourced from an already-running interactive shell — re-sourcing fails silently (`BLE_VERSION` stays unset, `ble-import` not found). The build-from-source path requires `gawk` (GNU awk); this Ubuntu 24.04 box only has `mawk`, so the prebuilt nightly tarball is used instead. fzf release asset filenames drop the `v` prefix (`fzf-0.74.1-linux_amd64.tar.gz`, not `fzf-v0.74.1-...`).

### Minimal prompt (2026-07-27)
Replaces the default `user@hostname dir %` with `dir branch %` — cwd in cyan, git branch in gray, `%` green normally / red after a failed command. Appended to `~/.zshrc`:

```zsh
# Minimal prompt: cwd + git branch, no user@host; % goes red on error
setopt PROMPT_SUBST
autoload -Uz vcs_info
precmd() { vcs_info }
zstyle ':vcs_info:git:*' formats ' %F{242}%b%f'
PROMPT='%F{cyan}%1~%f${vcs_info_msg_0_} %(?.%F{green}.%F{red})%#%f '
```

### Tab font size patch (2026-07-27)
Wave hardcodes tab-bar fonts at small sizes inside the bundled `app.asar` — no `tab:fontsize` config key exists (upstream request: [wavetermdev/waveterm#3203](https://github.com/wavetermdev/waveterm/issues/3203)). Wave has two tab placements (`app:tabbar` setting: `"top"` or `"left"`), rendered by completely different code paths:

- **Top tab bar** — CSS rule `.tab .name { font-size: 11px }` in the CSS bundle
- **Left sidebar** — Tailwind `text-xs` (12px) class on the `VTabBar` item div in the JS bundle (label child inherits it)

The patcher at `plugins/tab-font-patch/wave-tab-font-patch.sh` bumps **both** to 20px by repacking the asar, and re-applies itself after Wave auto-updates. The CSS patch uses a scoped regex on `.tab .name`; the JS patch replaces `text-xs` with `text-xl` (Tailwind: 12→14→16→18→20px for `text-xs/sm/base/lg/xl`; arbitrary values like `text-[17px]` aren't available in the pre-built bundle) in the exact `VTabBar` item className string and appends a marker class `wave-tab-font-patch-vtab-20px` for idempotency.

**Tab pill background (2026-07-31):** The patcher also appends a CSS rule `.tab,.wave-tab-font-patch-vtab-20px{background-color:#000000!important}` so each tab pill gets a flat black background in both placements (top bar `.tab` + left-sidebar VTabBar items). `!important` overrides Wave's hover/active/selected backgrounds so the pill stays black in every state. Config: `TAB_BG_COLOR` (default `#000000`; set to empty string to skip the bg patch).

**Badge icon size override (2026-07-29):** Wave's VTab `TabBadges` className includes `[&_i]:text-[10px]`, which forces the badge icon (spinner/check/bell) to 10px on the left sidebar — nearly invisible at that size. The patcher now also appends a CSS rule `.wave-tab-font-patch-vtab-20px i{font-size:14px!important}` to the CSS bundle, overriding the 10px to 14px. Uses the vtab marker class as a selector so it only affects left-sidebar tabs, not the top tab bar. Appended to the end of the CSS file so it wins the cascade (same specificity 0,1,1 as the `[&_i]:text-[10px]` rule — later wins; `!important` is belt-and-suspenders). Config: `VTAB_BADGE_ICON_SIZE` (default `14`). 14px fits in the 16px badge container (`h-[16px]`) without clipping.

Installed to `~/.config/waveterm/patch/wave-tab-font-patch.sh`; original asar backed up to `app.asar.orig`. Auto-reapply lives in `~/.zshrc` (not a LaunchAgent — macOS Sequoia TCC blocks LaunchAgents from writing to another app's bundle, but an interactive terminal can). Every new shell does an instant `grep` for the marker `wave-tab-font-patch:20px` in the asar; if missing, the patcher runs in the background.

```zsh
# Auto-reapply Wave Terminal tab font patch
if [[ -f /Users/jcallicott/Applications/Wave.app/Contents/Resources/app.asar ]] && \
   ! grep -q "wave-tab-font-patch:20px" /Users/jcallicott/Applications/Wave.app/Contents/Resources/app.asar 2>/dev/null; then
  ( bash /Users/jcallicott/.config/waveterm/patch/wave-tab-font-patch.sh >/dev/null 2>&1 & )
fi
```

Key invariants learned: repack with `--unpack "{dist/bin/*,dist/schema/*}"` or native binaries get packed in and Wave breaks; use `cp` not `mv` to replace the asar (running Wave has it memory-mapped, `mv` fails with "Operation not permitted"); only patch the `.tab .name` rule — there are ~10 other unrelated `font-size: 11px` rules in the same CSS bundle; **never replace `app.asar.unpacked/` with an asar-extracted copy** — `@electron/asar extract` does not preserve executable bits, so `wavesrv.arm64` and `wsh-*` lose `+x` and Wave fails with `EACCES` on spawn. The patcher leaves the unpacked dir untouched and defensively `chmod +x`s the binaries on every run. The main JS bundle must be located via `index.html`'s `<script src>` — there are multiple `index-*.js` files in the assets dir (main bundle + tiny chunks), so `find | head -1` picks the wrong one. The JS patch targets an exact className string in the minified bundle, so a future Wave version that changes the `VTabBar` item's class list will cause the JS patch to fail (script logs an error and exits without replacing the asar); the CSS patch is more resilient since it uses a scoped regex. See `plugins/tab-font-patch/README.md` for full details.

### Open links in Safari (2026-07-28)
Wave has no "which browser" setting — its `web:` keys are `defaultsearch`, `defaulturl`, `hidenav`, `openlinksinternally`, `partition`, `useragenttype`, `zoom`. External links go through Electron's `shell.openExternal(url)`, which always defers to the macOS default handler (Chrome here, kept deliberately for non-Horizon work).

Two changes make clicked links open in Safari:

1. `~/.config/waveterm/settings.json` → `"web:openlinksinternally": false` (was `true`, which routed links into Wave's internal browser so they never reached `openExternal`).
2. `plugins/safari-links-patch/wave-safari-links-patch.sh`, installed to `~/.config/waveterm/patch/`, injects a shim after the electron imports in `dist/main/index.js` wrapping `shell.openExternal` to spawn `open -a Safari <url>` for http(s) URLs on macOS. `file://`/`mailto:`/non-macOS fall through to the original. `shell` (named import) and `electron.shell` are the same object, so one wrap covers all seven call sites. `BROWSER_APP` env var targets a different browser.

Two repack traps cost a couple of restore-and-retry cycles here, both now guarded in the script (it verifies the header and refuses to install if either regresses):

- `--unpack "{dist/bin/*,dist/schema/*}"` is required — `--unpack-dir "{dist/bin,dist/schema}"` leaves `dist/schema/*` packed into the asar while the files still sit in `app.asar.unpacked/` on disk.
- The `--unpack` glob is evaluated **relative to CWD**. Packing an absolute source path (`asar pack "$WORK/app" out.asar --unpack ...`) matches nothing and packs the native binaries in, so Wave fails to spawn `wavesrv`. `cd` into the extracted tree and pack `.` — which is what tab-font-patch already did, and why it never hit this.

Ordering note: the two asar patches compose. Restore from `app.asar.orig` and re-run tab-font-patch then safari-links-patch to rebuild both from pristine.

## Machine setup log (Jay's Linux box — Ubuntu 24.04, 2026-07-29)

Parallel setup for the Linux workstation. Bash, not zsh. All asar patches and the badge symlink are identical to the Mac; differences are shell-specific.

### Wave Terminal
- Installed as AppImage extracted to `~/Applications/wave-terminal` (not `/opt/Wave` — the `wave-badges` README's `wsh` finder checks both). `wsh` found via `~/.local/share/waveterm/bin` on PATH.
- asar at `~/Applications/wave-terminal/resources/app.asar`; original backed up to `app.asar.orig`.

### asar patches
- tab-font-patch: installed to `~/.config/waveterm/patch/`, byte-identical to the repo script. Applied to the asar (markers `wave-tab-font-patch:20px`, `wave-tab-font-patch-vtab-20px`, `badge-icon-14px`, `bg-#000000` present).
- safari-links-patch: **not applied** — it's macOS-only (`open -a Safari`); on Linux it falls through to the original `shell.openExternal`, so there's nothing to patch. The script is still installed to `~/.config/waveterm/patch/` for repo parity but never run.

### Auto-reapply (bash, not zsh)
In `~/.bashrc` (not `~/.zshrc` — this is a bash box). Same grep-marker-then-background-run pattern as the Mac, but wrapped in `[ -f "$WAVE_ASAR" ]` with `WAVE_ASAR="$HOME/Applications/wave-terminal/resources/app.asar"`. Only checks the tab-font marker (safari-links skipped on Linux).

### Devin autostart in every Wave tab (2026-07-29, updated 2026-07-29)
Wave spawns Devin directly as the tab shell — no bash, no prompt flash. Two pieces:

**`~/.config/waveterm/devin-launcher.sh`** — a tiny wrapper script set as `term:localshellpath` in `~/.config/waveterm/settings.json`. It reaps the asar patch check (moved here from `.bashrc` because Wave no longer spawns bash in new tabs), sets `DEVIN_AUTOSTARTED=1` (belt-and-suspenders recursion guard), and `exec`s devin. Devin is a compiled static binary — it doesn't need Node/nvm/PATH to start. Its exec tool spawns bash, which reads `~/.bashrc` and gets the full env (PATH, API keys, nvm, deno, ble.sh) for the commands it runs.

**`~/.bashrc` fallback guard** — kept in case a Wave-spawned interactive bash somehow bypasses the custom shell path (e.g. a split pane that falls back to bash). Same guard as before: `WAVETERM=1` + interactive `$-` + `DEVIN_AUTOSTARTED` unset → `exec devin -c --permission-mode=dangerous`. Devin's own exec tool spawns non-interactive shells (`$-` = `hBc`) that also inherit `DEVIN_AUTOSTARTED=1`, so there's no recursion.

`devin -c` resumes the most recent session in the current directory (starts a new one if none exists). `exec` replaces the shell — the tab closes when Devin exits. The asar patch auto-reapply moved from `.bashrc` to the launcher script because new Wave tabs no longer run bash; the `.bashrc` copy is kept for non-Wave interactive shells.
