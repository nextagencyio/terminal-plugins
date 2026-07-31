# tab-font-patch

Wave Terminal has no built-in setting for tab-bar font size — tabs are hardcoded at small sizes inside the bundled `app.asar`. Upstream feature request: [wavetermdev/waveterm#3203](https://github.com/wavetermdev/waveterm/issues/3203).

Wave has two tab placements (`app:tabbar` setting: `"top"` or `"left"`), and they're rendered by completely different code paths:

- **Top tab bar** — CSS rule `.tab .name { font-size: 11px }` in the CSS bundle
- **Left sidebar** — Tailwind `text-xs` (12px) class on the `VTabBar` item div in the JS bundle (the label child inherits it)

This patcher bumps **both** to a larger size (default **20px**) and applies a flat black background to each tab pill, by repacking the asar, and re-applies itself automatically after Wave auto-updates overwrite it.

## Install

```sh
mkdir -p ~/.config/waveterm/patch
cp plugins/tab-font-patch/wave-tab-font-patch.sh ~/.config/waveterm/patch/
chmod +x ~/.config/waveterm/patch/wave-tab-font-patch.sh
bash ~/.config/waveterm/patch/wave-tab-font-patch.sh
```

Then add the auto-reapply snippet to `~/.zshrc` (see below).

Restart Wave for the change to take effect — the running process has the old asar memory-mapped and is unaffected by the patch; the next launch picks up the new content.

## Auto-reapply

macOS Sequoia's TCC/App Management protection blocks LaunchAgents from writing to another app's bundle (`Operation not permitted`), but an interactive terminal has that permission. So the auto-reapply check lives in `~/.zshrc` rather than a LaunchAgent: every new shell does an instant `grep` for the patch marker in the asar, and if it's missing (Wave updated), the patcher runs silently in the background.

Append to `~/.zshrc`:

```zsh
# Auto-reapply Wave Terminal tab font patch (runs in background, instant
# no-op if already patched). LaunchAgents can't write to the app bundle on
# macOS Sequoia (TCC/App Management), but the terminal can — so we check
# here every time a shell opens.
if [[ -f /Users/jcallicott/Applications/Wave.app/Contents/Resources/app.asar ]] && \
   ! grep -q "wave-tab-font-patch:20px" /Users/jcallicott/Applications/Wave.app/Contents/Resources/app.asar 2>/dev/null; then
  ( bash /Users/jcallicott/.config/waveterm/patch/wave-tab-font-patch.sh >/dev/null 2>&1 & )
fi
```

> The hardcoded user path is Jay's machine preference — generalize `WAVE_APP_PATH` and the grep path for other setups, or move them to env vars.

## How it works

1. Extracts `app.asar` with `@electron/asar`
2. **CSS patch** — patches only the `.tab .name { font-size: 11px }` rule (scoped regex — leaves the other ~10 unrelated `11px` rules in the bundle alone); injects marker comment `/* wave-tab-font-patch:20px */`. Also appends a rule applying `TAB_BG_COLOR` (default `#000000`) to `.tab` and the vtab marker class, so each tab pill gets a flat black background in both placements
3. **JS patch** — finds the main JS bundle (the `index-*.js` referenced in `index.html` — there are multiple `index-*.js` files, so `find | head -1` is unreliable) and replaces the `text-xs` Tailwind class in the `VTabBar` item's exact className string with the mapped class (e.g. `text-xl`); appends a marker class `wave-tab-font-patch-vtab-20px` for idempotency
4. Repacks with `--unpack "{dist/bin/*,dist/schema/*}"` so native binaries and schema files stay on disk (matches Wave's original build config — packing them into the asar would make them unexecutable and break Wave)
5. Replaces the asar with `cp` (not `mv`) so it works while Wave is running — `mv` fails with "Operation not permitted" because the running Wave has the asar memory-mapped
6. Original asar backed up to `app.asar.orig` on first run

The left sidebar uses Tailwind utility classes, so the vtab size maps to the closest standard class: `text-xs` (12px), `text-sm` (14px), `text-base` (16px), `text-lg` (18px), `text-xl` (20px). Arbitrary values like `text-[17px]` are not available because they'd only exist if Tailwind's JIT had compiled them into the pre-built CSS bundle.

## Config

| Env var | Default | Purpose |
|---|---|---|
| `TAB_FONT_SIZE` | `20` | Top tab bar font size in px |
| `VTAB_FONT_SIZE` | `= TAB_FONT_SIZE` | Left sidebar tab font size in px (snaps to nearest Tailwind class) |
| `TAB_BG_COLOR` | `#000000` | Background color applied to each tab pill (top bar `.tab` + left-sidebar items). Set to empty string to skip the bg patch. |
| `WAVE_APP_PATH` | `/Users/jcallicott/Applications/Wave.app` | Wave app bundle path |

To change the size: edit `TAB_FONT_SIZE` / `VTAB_FONT_SIZE` at the top of the script **and** update the marker string in your `.zshrc` snippet to match (e.g. `wave-tab-font-patch:20px`), then restore from `app.asar.orig` and run the script once manually (the patcher won't re-patch an already-patched asar — it detects markers and no-ops).

## Caveats

- Gets wiped on each Wave auto-update — that's what the auto-reapply handles
- Modifies the app bundle; Wave isn't notarized-gated in practice, but macOS may show a one-time Gatekeeper prompt on a fresh install (unrelated to this patch)
- The patcher touches the CSS and JS bundles; `app.asar.unpacked/` (native binaries) is left intact since its content is identical between original and patched asar
- The JS patch targets an exact className string in the minified bundle — a future Wave version that changes the `VTabBar` item's class list will cause the JS patch to fail (the script logs an error and exits without replacing the asar); the CSS patch is more resilient since it uses a scoped regex
