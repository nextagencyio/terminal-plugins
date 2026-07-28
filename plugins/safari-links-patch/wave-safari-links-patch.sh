#!/usr/bin/env bash
# wave-safari-links-patch.sh
#
# Idempotently patches Wave Terminal's bundled app.asar so links clicked inside
# Wave open in **Safari** instead of the macOS default browser (Chrome here).
#
# Why a patch: Wave has no "which browser" setting. Its `web:` settings are
# defaultsearch / defaulturl / hidenav / openlinksinternally / partition /
# useragenttype / zoom. External links go through Electron's
# `shell.openExternal(url)`, which always defers to the OS default handler.
#
# What it does: injects a shim after the electron imports in dist/main/index.js
# that wraps `shell.openExternal` and spawns `open -a Safari <url>` for http(s)
# URLs on macOS. Everything else (file://, mailto:, other platforms) falls
# through to the original implementation. `shell` and `electron.shell` are the
# same object, so wrapping it once covers all call sites.
#
# Pair with `"web:openlinksinternally": false` in ~/.config/waveterm/settings.json
# — otherwise links open in Wave's internal browser and never reach this path.
#
# Re-applies itself after Wave auto-updates replace app.asar. Safe to run
# repeatedly: detects an already-patched asar and no-ops. Original asar is
# backed up once to app.asar.orig.
#
# Uses `cp` (not `mv`) to replace the asar so it works even while Wave is
# running — the running process has the old asar memory-mapped and is
# unaffected; the next launch picks up the patched content.
#
# Config:
#   BROWSER_APP   (default Safari)  — any macOS app name `open -a` accepts
#   WAVE_APP_PATH (default /Users/jcallicott/Applications/Wave.app)

set -uo pipefail

BROWSER_APP="${BROWSER_APP:-Safari}"
WAVE_APP_PATH="${WAVE_APP_PATH:-/Users/jcallicott/Applications/Wave.app}"
ASAR="$WAVE_APP_PATH/Contents/Resources/app.asar"
BACKUP="$ASAR.orig"
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$PATCH_DIR/patch.log"
MARKER="__waveSafariOpenExternal"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$LOG_FILE"; }

[ -f "$ASAR" ] || { echo "app.asar not found at $ASAR" >&2; log "abort: no asar at $ASAR"; exit 1; }

log "extracting asar (safari-links)"
npx --yes @electron/asar extract "$ASAR" "$WORK_DIR/app" >/dev/null 2>&1 || {
  echo "asar extract failed" >&2; log "abort: extract failed"; exit 1; }

MAIN="$WORK_DIR/app/dist/main/index.js"
[ -f "$MAIN" ] || { echo "dist/main/index.js missing" >&2; log "abort: no main bundle"; exit 1; }

if grep -q "$MARKER" "$MAIN"; then
  log "already patched (browser=$BROWSER_APP) — no-op"
  echo "Wave already patched to open links in $BROWSER_APP — nothing to do."
  exit 0
fi

BROWSER_APP="$BROWSER_APP" MAIN="$MAIN" python3 - <<'PYEOF' || { echo "injection failed" >&2; exit 1; }
import os, re, sys

main = os.environ["MAIN"]
browser = os.environ["BROWSER_APP"]
src = open(main, encoding="utf-8").read()

# Anchor: the named electron import, which brings `shell` into scope.
anchor = re.search(r'^import electron__default, \{[^}]*\} from "electron";', src, re.M)
if not anchor:
    print("anchor import not found", file=sys.stderr); sys.exit(1)

shim = '''
import { spawn as __waveSafariSpawn } from "child_process";
// __waveSafariOpenExternal: route http(s) links to %(browser)s instead of the
// macOS default browser. Injected by wave-safari-links-patch.sh.
(() => {
  try {
    const __waveSafariOpenExternal = shell.openExternal.bind(shell);
    shell.openExternal = (url, options) => {
      try {
        const u = String(url == null ? "" : url);
        if (process.platform === "darwin" && /^https?:\\/\\//i.test(u)) {
          __waveSafariSpawn("open", ["-a", "%(browser)s", u], {
            detached: true,
            stdio: "ignore",
          }).unref();
          return Promise.resolve();
        }
      } catch (e) {}
      return __waveSafariOpenExternal(url, options);
    };
  } catch (e) {}
})();
''' % {"browser": browser}

pos = anchor.end()
open(main, "w", encoding="utf-8").write(src[:pos] + shim + src[pos:])
print("injected")
PYEOF

if [ ! -f "$BACKUP" ]; then
  cp "$ASAR" "$BACKUP"
  log "backed up original asar -> $(basename "$BACKUP")"
fi

log "repacking asar"
# Must match the ORIGINAL asar's unpack spec exactly, or the header marks
# files differently than app.asar.unpacked/ on disk (native binaries packed
# in = Wave fails to spawn wavesrv). Two traps: use `--unpack` (glob), not
# `--unpack-dir`; and the glob is evaluated relative to CWD, so cd into the
# extracted tree and pack `.` rather than passing an absolute path.
( cd "$WORK_DIR/app" && npx --yes @electron/asar pack . "$WORK_DIR/app.asar" \
    --unpack "{dist/bin/*,dist/schema/*}" ) >/dev/null 2>&1 || {
  echo "asar pack failed" >&2; log "abort: pack failed"; exit 1; }

# Verify the header kept native binaries unpacked before we replace anything.
python3 - "$WORK_DIR/app.asar" <<'PYEOF' || { echo "unpack-flag verification failed" >&2; log "abort: header verification failed"; exit 1; }
import json, struct, sys
with open(sys.argv[1], "rb") as f:
    f.read(12); size = struct.unpack("<I", f.read(4))[0]
    h = json.loads(f.read(size).split(b"\x00")[0].decode("utf-8"))
for path in ("dist/bin", "dist/schema"):
    cur = h
    for part in path.split("/"):
        cur = cur["files"][part]
    first = next(iter(cur.get("files", {}).values()), {})
    if not first.get("unpacked"):
        print(f"{path} is PACKED — refusing to install", file=sys.stderr)
        sys.exit(1)
PYEOF

log "replacing asar (cp)"
cp "$WORK_DIR/app.asar" "$ASAR"
log "patched: links open in $BROWSER_APP; takes effect on next Wave launch"
echo "Patched — Wave will open links in $BROWSER_APP after its next launch."
