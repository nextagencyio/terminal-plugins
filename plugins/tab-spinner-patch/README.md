# tab-spinner-patch

Wave Terminal shows a "waiting" / running indicator on tabs as a Font Awesome icon with the `fa-spin` modifier — a continuous 360° rotation at 2s/revolution. It's the same spinner used everywhere in the app, but on a tab you stare at for long runs (a build, an agent session) it gets visually tiring.

This patcher keeps Wave's original spinner icon glyph but swaps the `fa-spin` rotation for a **color pulse** (opacity 0.25 ↔ 1.0 over 1.8s, ease-in-out) on **tab badges only**. The icon stays visible and fades in/out instead of spinning. Other spinners in the app (block headers, secret dialogs, app lists, etc.) are untouched.

## Install

```sh
mkdir -p ~/.config/waveterm/patch
cp plugins/tab-spinner-patch/wave-tab-spinner-patch.sh ~/.config/waveterm/patch/
chmod +x ~/.config/waveterm/patch/wave-tab-spinner-patch.sh
bash ~/.config/waveterm/patch/wave-tab-spinner-patch.sh
```

Then add the auto-reapply snippet to `~/.zshrc` (see below).

Restart Wave for the change to take effect — the running process has the old asar memory-mapped and is unaffected by the patch; the next launch picks up the new content.

## Auto-reapply

Same approach as the other asar patches: macOS Sequoia TCC blocks LaunchAgents from writing to another app's bundle, but an interactive terminal can. Every new shell greps the asar for the patch marker; if missing (Wave updated), the patcher runs silently in the background.

Append to `~/.zshrc` (alongside the tab-font and safari-links snippets):

```zsh
if ! grep -q "wave-tab-spinner-patch" /Users/jcallicott/Applications/Wave.app/Contents/Resources/app.asar 2>/dev/null; then
  ( bash /Users/jcallicott/.config/waveterm/patch/wave-tab-spinner-patch.sh >/dev/null 2>&1 & )
fi
```

> The hardcoded user path is Jay's machine preference — generalize `WAVE_APP_PATH` and the grep path for other setups.

## How it works

1. Extracts `app.asar` with `@electron/asar`
2. **JS patch** — in the shared `TabBadges` component (the single render path for BOTH the top tab bar and the left sidebar vtab), the firstBadge `<i>` className is built from `makeIconClass(firstBadge.icon, true, { defaultIcon: "circle-small" }) + " text-[12px]"`. The patch appends `.replace("fa-spin", "wave-tab-pulse")` so any spinning tab badge icon pulses instead of rotating. One patch site covers both tab placements.
3. **CSS patch** — appends a `.wave-tab-pulse` animation rule + `@keyframes wave-tab-pulse` (opacity 0.4 → 1 → 0.4, ease-in-out, infinite); injects marker comment `/* wave-tab-spinner-patch */`
4. Repacks with `--unpack "{dist/bin/*,dist/schema/*}"` so native binaries and schema files stay on disk
5. Replaces the asar with `cp` (not `mv`) so it works while Wave is running
6. Original asar backed up to `app.asar.orig` on first run (shared with the other wave-* patches)

### Why only tab badges

The tab "waiting" spinner is a badge icon routed through `TabBadges` → `makeIconClass(...)`, which appends `fa-spin` when the badge icon string has a `+spin` modifier. Other spinners in the app (block headers, dialogs, app lists) use different render paths that don't go through `TabBadges`' firstBadge `<i>`, so they keep their normal rotation. This keeps the change scoped to the thing that was actually annoying.

## Config

| Env var | Default | Purpose |
|---|---|---|
| `WAVE_APP_PATH` | `/Users/jcallicott/Applications/Wave.app` | Wave app bundle path |
| `PULSE_DURATION` | `1.8s` | Pulse animation duration |
| `PULSE_MIN_OPACITY` | `0.25` | Minimum opacity at pulse trough (0–1) |

To change the pulse feel: edit the env vars (or the defaults at the top of the script), restore from `app.asar.orig`, and run the script once manually (the patcher won't re-patch an already-patched asar — it detects markers and no-ops).

## Composes with other patches

The three asar patches (tab-font, safari-links, tab-spinner) compose. To rebuild all from pristine: restore from `app.asar.orig` and run tab-font-patch → safari-links-patch → tab-spinner-patch.

## Caveats

- Gets wiped on each Wave auto-update — that's what the auto-reapply handles
- The JS patch targets an exact className expression in the minified bundle — a future Wave version that changes `TabBadges`' firstBadge render will cause the JS patch to fail (the script logs an error and exits without replacing the asar); the CSS patch is self-contained and resilient
- Only affects tab badges; block-header spinners and other `fa-spin` usages elsewhere are untouched
