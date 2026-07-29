# AGENTS.md

Working notes for AI agents (and future humans) contributing to this repo. Everything done for this setup — even one-off machine config — gets recorded here or committed as code. If you change the environment, update this file in the same commit.

## Repo purpose

Wave Terminal integrations for AI agent CLIs, published three ways from one repo:

- **Claude Code plugin marketplace** — `.claude-plugin/marketplace.json` at root, plugin at `plugins/wave-badges/` (hooks auto-load from `hooks/hooks.json`; do NOT add a `"hooks"` key to `plugin.json` — Claude Code treats it as a duplicate and the plugin fails to load; see commit 6807b60)
- **Devin CLI plugin** — `.devin-plugin/plugin.json` + `skills/` at root (Devin plugins are skill bundles only; actual hook wiring is done by `plugins/wave-badges/install-devin.sh`)
- **opencode plugin** — `plugins/wave-badges/opencode/wave-badge.js`, symlinked by `install-opencode.sh`

## Conventions

- Commits and pushes are attributed to **nextagencyio** (`jrcallicott@gmail.com`), never a work account. The local clone has repo-local `user.name`/`user.email` and a credential helper that shells to `gh auth token -u nextagencyio`.
- The canonical badge script is `plugins/wave-badges/bin/wave-badge`; `~/.local/bin/wave-badge` is a symlink to it, so Devin and opencode pick up edits immediately. Claude Code installs the plugin from GitHub, so it only sees **pushed** changes after a session restart or `/plugin` update.
- The script must stay a silent no-op outside Wave (`$WAVETERM_BLOCKID` guard, `exit 0` everywhere) — it lives in configs shared across terminals.
- Wave badge invariants (learned from Wave source): FontAwesome icons only (`+spin/+beat/+fade` suffixes); Wave never replaces a badge with a lower-priority one, so always clear-before-set; focus auto-clear skips pid-linked badges (`--pid`), which is how badges persist until session exit.
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

### Shell QoL (2026-07-27)
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

The patcher at `plugins/tab-font-patch/wave-tab-font-patch.sh` bumps **both** to 18px by repacking the asar, and re-applies itself after Wave auto-updates. The CSS patch uses a scoped regex on `.tab .name`; the JS patch replaces `text-xs` with `text-lg` (Tailwind: 12→14→16→18→20px for `text-xs/sm/base/lg/xl`; arbitrary values like `text-[17px]` aren't available in the pre-built bundle) in the exact `VTabBar` item className string and appends a marker class `wave-tab-font-patch-vtab-18px` for idempotency.

Installed to `~/.config/waveterm/patch/wave-tab-font-patch.sh`; original asar backed up to `app.asar.orig`. Auto-reapply lives in `~/.zshrc` (not a LaunchAgent — macOS Sequoia TCC blocks LaunchAgents from writing to another app's bundle, but an interactive terminal can). Every new shell does an instant `grep` for the marker `wave-tab-font-patch:18px` in the asar; if missing, the patcher runs in the background.

```zsh
# Auto-reapply Wave Terminal tab font patch
if [[ -f /Users/jcallicott/Applications/Wave.app/Contents/Resources/app.asar ]] && \
   ! grep -q "wave-tab-font-patch:18px" /Users/jcallicott/Applications/Wave.app/Contents/Resources/app.asar 2>/dev/null; then
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

### Tab spinner → subtle pulse (2026-07-29)
Wave's tab "waiting" / running indicator is a Font Awesome badge icon with the `fa-spin` modifier (continuous 360° rotation at 2s/rev) — visually tiring on tabs you stare at for long runs. `plugins/tab-spinner-patch/wave-tab-spinner-patch.sh`, installed to `~/.config/waveterm/patch/`, swaps that rotation for a gentle opacity pulse (0.4 ↔ 1.0 over 1.8s, ease-in-out) on **tab badges only**.

The tab waiting spinner is a badge routed through the shared `TabBadges` component (the single render path for BOTH the top tab bar and the left sidebar vtab), which calls `makeIconClass(firstBadge.icon, true, { defaultIcon: "circle-small" }) + " text-[12px]"` to build the `<i>` className. `makeIconClass` appends `fa-spin` when the badge icon string has a `+spin` modifier. The JS patch appends `.replace("fa-spin", "wave-tab-pulse")` to that one expression, so a single patch site covers both tab placements. The CSS patch appends a `.wave-tab-pulse` animation + `@keyframes wave-tab-pulse` rule (opacity pulse, no rotation). Other spinners in the app (block headers, secret dialogs, app lists) use different render paths that don't go through `TabBadges`' firstBadge `<i>`, so they keep their normal rotation — the change is scoped to the thing that was actually annoying.

Auto-reapply added to the same `~/.zshrc` block as tab-font-patch (grep for `wave-tab-spinner-patch` marker in the asar; run in background if missing). The three asar patches (tab-font, safari-links, tab-spinner) compose; rebuild all from pristine by restoring `app.asar.orig` and running tab-font-patch → safari-links-patch → tab-spinner-patch. Config: `PULSE_DURATION` (default `1.8s`), `PULSE_MIN_OPACITY` (default `0.4`).
