# tab-font-patch

Wave Terminal has no built-in setting for tab-bar font size — the tab label is hardcoded at `font-size: 11px` in `tab.scss` inside the bundled `app.asar`. Upstream feature request: [wavetermdev/waveterm#3203](https://github.com/wavetermdev/waveterm/issues/3203).

This patcher bumps `.tab .name` to a larger size (default **18px**) by repacking the asar, and re-applies itself automatically after Wave auto-updates overwrite it.

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
   ! grep -q "wave-tab-font-patch:18px" /Users/jcallicott/Applications/Wave.app/Contents/Resources/app.asar 2>/dev/null; then
  ( bash /Users/jcallicott/.config/waveterm/patch/wave-tab-font-patch.sh >/dev/null 2>&1 & )
fi
```

> The hardcoded user path is Jay's machine preference — generalize `WAVE_APP_PATH` and the grep path for other setups, or move them to env vars.

## How it works

1. Extracts `app.asar` with `@electron/asar`
2. Patches only the `.tab .name { font-size: 11px }` rule (scoped regex — leaves the other ~10 unrelated `11px` rules in the bundle alone)
3. Injects a marker comment `/* wave-tab-font-patch:18px */` so it can detect an already-patched asar and no-op
4. Repacks with `--unpack "{dist/bin/*,dist/schema/*}"` so native binaries and schema files stay on disk (matches Wave's original build config — packing them into the asar would make them unexecutable and break Wave)
5. Replaces the asar with `cp` (not `mv`) so it works while Wave is running — `mv` fails with "Operation not permitted" because the running Wave has the asar memory-mapped
6. Original asar backed up to `app.asar.orig` on first run

## Config

| Env var | Default | Purpose |
|---|---|---|
| `TAB_FONT_SIZE` | `18` | Tab label font size in px |
| `WAVE_APP_PATH` | `/Users/jcallicott/Applications/Wave.app` | Wave app bundle path |

To change the size: edit `TAB_FONT_SIZE` at the top of the script **and** update the marker string in your `.zshrc` snippet to match (e.g. `wave-tab-font-patch:16px`), then run the script once manually.

## Caveats

- Gets wiped on each Wave auto-update — that's what the auto-reapply handles
- Modifies the app bundle; Wave isn't notarized-gated in practice, but macOS may show a one-time Gatekeeper prompt on a fresh install (unrelated to this patch)
- The patcher only touches the CSS bundle; `app.asar.unpacked/` (native binaries) is left intact since its content is identical between original and patched asar
