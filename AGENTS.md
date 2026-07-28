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
Wave hardcodes the tab-bar label at `font-size: 11px` in `tab.scss` inside the bundled `app.asar` — no `tab:fontsize` config key exists (upstream request: [wavetermdev/waveterm#3203](https://github.com/wavetermdev/waveterm/issues/3203)). The patcher at `plugins/tab-font-patch/wave-tab-font-patch.sh` bumps `.tab .name` to 18px by repacking the asar, and re-applies itself after Wave auto-updates.

Installed to `~/.config/waveterm/patch/wave-tab-font-patch.sh`; original asar backed up to `app.asar.orig`. Auto-reapply lives in `~/.zshrc` (not a LaunchAgent — macOS Sequoia TCC blocks LaunchAgents from writing to another app's bundle, but an interactive terminal can). Every new shell does an instant `grep` for the marker `wave-tab-font-patch:18px` in the asar; if missing, the patcher runs in the background.

```zsh
# Auto-reapply Wave Terminal tab font patch
if [[ -f /Users/jcallicott/Applications/Wave.app/Contents/Resources/app.asar ]] && \
   ! grep -q "wave-tab-font-patch:18px" /Users/jcallicott/Applications/Wave.app/Contents/Resources/app.asar 2>/dev/null; then
  ( bash /Users/jcallicott/.config/waveterm/patch/wave-tab-font-patch.sh >/dev/null 2>&1 & )
fi
```

Key invariants learned: repack with `--unpack "{dist/bin/*,dist/schema/*}"` or native binaries get packed in and Wave breaks; use `cp` not `mv` to replace the asar (running Wave has it memory-mapped, `mv` fails with "Operation not permitted"); only patch the `.tab .name` rule — there are ~10 other unrelated `font-size: 11px` rules in the same CSS bundle; **never replace `app.asar.unpacked/` with an asar-extracted copy** — `@electron/asar extract` does not preserve executable bits, so `wavesrv.arm64` and `wsh-*` lose `+x` and Wave fails with `EACCES` on spawn. The patcher now leaves the unpacked dir untouched and defensively `chmod +x`s the binaries on every run. See `plugins/tab-font-patch/README.md` for full details.
