# safari-links-patch

Makes links clicked inside Wave Terminal open in **Safari** instead of the
macOS default browser.

## Why a patch

Wave has no setting for which browser to use. Its `web:` keys are
`defaultsearch`, `defaulturl`, `hidenav`, `openlinksinternally`, `partition`,
`useragenttype`, `zoom` — none of them select a browser. External links go
through Electron's `shell.openExternal(url)`, which always defers to the OS
default handler (Chrome on this machine, deliberately).

## What it does

Injects a shim after the electron imports in `dist/main/index.js` that wraps
`shell.openExternal` and spawns `open -a Safari <url>` for http(s) URLs on
macOS. `file://`, `mailto:`, and non-macOS fall through to the original
implementation. `shell` (named import) and `electron.shell` are the same
object, so wrapping it once covers all seven call sites in the bundle.

Requires `"web:openlinksinternally": false` in
`~/.config/waveterm/settings.json` — otherwise links open in Wave's internal
browser and never reach `openExternal`.

## Install

```sh
cp wave-safari-links-patch.sh ~/.config/waveterm/patch/
chmod +x ~/.config/waveterm/patch/wave-safari-links-patch.sh
~/.config/waveterm/patch/wave-safari-links-patch.sh
```

Takes effect on the next Wave launch. Idempotent — detects an already-patched
asar and no-ops. Set `BROWSER_APP=Firefox` (or any app `open -a` accepts) to
target a different browser.

## Repack invariants (shared with tab-font-patch)

Both learned the hard way here:

- Use `--unpack "{dist/bin/*,dist/schema/*}"`, **not** `--unpack-dir`. The
  latter leaves `dist/schema/*` packed into the asar while the files still sit
  in `app.asar.unpacked/` on disk.
- The `--unpack` glob is evaluated **relative to CWD**, so `cd` into the
  extracted tree and pack `.`. Passing an absolute source path silently
  matches nothing and packs the native binaries in — Wave then fails to spawn
  `wavesrv`.

The script verifies the repacked header still marks `dist/bin` and
`dist/schema` as unpacked and refuses to install if not. Replace the asar with
`cp`, never `mv` — a running Wave has it memory-mapped.
