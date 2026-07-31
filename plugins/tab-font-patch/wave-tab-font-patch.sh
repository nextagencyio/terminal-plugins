#!/usr/bin/env bash
# wave-tab-font-patch.sh
#
# Idempotently patches Wave Terminal's bundled app.asar to enlarge tab fonts
# in BOTH tab placements:
#   1. Top tab bar  — CSS rule `.tab .name { font-size: 11px }` -> $TAB_FONT_SIZE px
#   2. Left sidebar — Tailwind `text-xs` (12px) on the VTabBar item -> matching class
# Re-applies itself after Wave auto-updates replace app.asar.
#
# Safe to run repeatedly: detects an already-patched asar and no-ops.
# Original asar is backed up once to app.asar.orig.
#
# Uses `cp` (not `mv`) to replace the asar so it works even while Wave is
# running — the running process has the old asar memory-mapped and is
# unaffected; the next launch picks up the patched content.
#
# The app.asar.unpacked/ directory is NOT touched: it only contains native
# binaries (dist/bin/*) and schema files (dist/schema/*), which are identical
# between the original and patched asar. The repacked asar's header marks
# the same files as unpacked (same --unpack glob), so it stays consistent
# with the existing unpacked dir.
#
# Config:
#   TAB_FONT_SIZE  (default 18)  — top tab bar, in px
#   VTAB_FONT_SIZE (default = TAB_FONT_SIZE) — left sidebar tabs, in px
#   WAVE_APP_PATH  (default platform-specific — see below)
#
# The left sidebar uses Tailwind utility classes (text-xs/text-sm/text-base/
# text-lg/text-xl = 12/14/16/18/20px). Non-standard sizes fall back to the
# nearest standard class. To change sizes after patching, restore from
# app.asar.orig and re-run.

set -uo pipefail

TAB_FONT_SIZE="${TAB_FONT_SIZE:-18}"
VTAB_FONT_SIZE="${VTAB_FONT_SIZE:-$TAB_FONT_SIZE}"
# Badge icon size on the left sidebar. Wave hardcodes [&_i]:text-[10px] on
# the VTab TabBadges className, making the spinner/check/bell icon 10px —
# nearly invisible at that size. This CSS override enlarges it. 14px fits
# in the 16px badge container without clipping.
VTAB_BADGE_ICON_SIZE="${VTAB_BADGE_ICON_SIZE:-14}"

# Platform-specific defaults: macOS uses Wave.app bundle, Linux uses the
# AppImage-style directory. WAVE_APP_PATH can be overridden via env.
if [[ "$(uname -s)" == "Darwin" ]]; then
  WAVE_APP_PATH="${WAVE_APP_PATH:-/Users/jcallicott/Applications/Wave.app}"
  ASAR="$WAVE_APP_PATH/Contents/Resources/app.asar"
else
  WAVE_APP_PATH="${WAVE_APP_PATH:-$HOME/Applications/wave-terminal}"
  ASAR="$WAVE_APP_PATH/resources/app.asar"
fi
BACKUP="$ASAR.orig"
PATCH_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_FILE="$PATCH_DIR/patch.log"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

log() { printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S')" "$*" >> "$LOG_FILE"; }

# Map a pixel size to the closest Tailwind text-size class that exists in
# Wave's pre-built CSS bundle (arbitrary values like text-[17px] are NOT
# available — they'd only exist if Tailwind's JIT had compiled them).
px_to_tw_class() {
  case "$1" in
    12) echo "text-xs" ;;
    14) echo "text-sm" ;;
    16) echo "text-base" ;;
    18) echo "text-lg" ;;
    20) echo "text-xl" ;;
    *)  # snap to nearest standard size
      if   [[ "$1" -le 13 ]]; then echo "text-xs"
      elif [[ "$1" -le 15 ]]; then echo "text-sm"
      elif [[ "$1" -le 17 ]]; then echo "text-base"
      elif [[ "$1" -le 19 ]]; then echo "text-lg"
      else echo "text-xl"
      fi ;;
  esac
}

# --- preconditions ---------------------------------------------------------
if [[ ! -f "$ASAR" ]]; then
  log "asar not found at $ASAR — Wave not installed? skipping"
  exit 0
fi

if ! command -v npx >/dev/null 2>&1; then
  log "ERROR: npx not on PATH — node/npm required"
  exit 0
fi

ASAR_BIN=(npx --yes @electron/asar)
CSS_MARKER="/* wave-tab-font-patch:${TAB_FONT_SIZE}px */"
VTAB_TW_CLASS="$(px_to_tw_class "$VTAB_FONT_SIZE")"
VTAB_MARKER_CLASS="wave-tab-font-patch-vtab-${VTAB_FONT_SIZE}px"
UNPACK_DIR_PATH="${ASAR%.asar}.asar.unpacked"

# --- ensure native binaries are executable ---------------------------------
# @electron/asar extract does NOT preserve executable bits, and a prior version
# of this script once replaced the unpacked dir with one extracted by asar
# (which stripped +x), causing Wave to fail with EACCES on wavesrv.arm64.
# This script no longer touches the unpacked dir, but we defensively chmod
# the binaries on every run in case a Wave update or other tool changed them.
if [[ -d "$UNPACK_DIR_PATH/dist/bin" ]]; then
  chmod +x "$UNPACK_DIR_PATH/dist/bin/"* 2>/dev/null || true
fi

# --- extract ---------------------------------------------------------------
log "extracting asar"
"${ASAR_BIN[@]}" extract "$ASAR" "$WORK_DIR/extracted" 2>/dev/null

CSS_REL=$(find "$WORK_DIR/extracted/dist/frontend/assets" -maxdepth 1 -name 'index-*.css' | head -1)
if [[ -z "$CSS_REL" ]]; then
  log "ERROR: could not locate index-*.css in extracted asar"
  exit 0
fi
CSS_FILE="$WORK_DIR/extracted/dist/frontend/assets/$(basename "$CSS_REL")"

# Find the main JS bundle — the one referenced in index.html. There are
# multiple index-*.js files in the assets dir (the main bundle + tiny chunks),
# so `find | head -1` is unreliable. The entry-point script src is the
# reliable selector.
JS_BASENAME="$(grep -oE 'src="\./assets/(index-[^"]+\.js)"' "$WORK_DIR/extracted/dist/frontend/index.html" | sed -E 's/^src="\.\/assets\///; s/"$//')"
if [[ -z "$JS_BASENAME" ]]; then
  log "ERROR: could not locate entry-point index-*.js in index.html"
  exit 0
fi
JS_FILE="$WORK_DIR/extracted/dist/frontend/assets/$JS_BASENAME"

# --- check what's already patched ------------------------------------------
CSS_DONE=0
JS_DONE=0
grep -qF "$CSS_MARKER" "$CSS_FILE" && CSS_DONE=1
grep -qF "$VTAB_MARKER_CLASS" "$JS_FILE" && JS_DONE=1

if [[ $CSS_DONE -eq 1 && $JS_DONE -eq 1 ]]; then
  log "already patched (css=${TAB_FONT_SIZE}px, vtab=${VTAB_FONT_SIZE}px) — no-op"
  exit 0
fi

# --- backup (only first time) ----------------------------------------------
if [[ ! -f "$BACKUP" ]]; then
  cp "$ASAR" "$BACKUP"
  log "backed up original asar -> $BACKUP"
fi

CHANGED=0

# --- patch CSS: top tab bar (.tab .name font-size) -------------------------
# Replace ONLY the `.tab .name` rule's font-size: 11px. Scoped regex so we
# don't touch the other ~10 unrelated `font-size: 11px` rules in the bundle.
if [[ $CSS_DONE -eq 0 ]]; then
  if python3 - "$CSS_FILE" "$TAB_FONT_SIZE" "$CSS_MARKER" <<'PY'
import re, sys
path, size, marker = sys.argv[1], sys.argv[2], sys.argv[3]
css = open(path).read()
pat = re.compile(r'(\.tab \.name \s*\{[^}]*?font-size:\s*)11px', re.DOTALL)
new, n = pat.subn(lambda m: f'{m.group(1)}{size}px {marker}', css, count=1)
if n != 1:
    print(f'ERROR: expected 1 match, replaced {n}', file=sys.stderr)
    sys.exit(1)
open(path, 'w').write(new)
print(f"patched 1 occurrence -> {size}px")
PY
  then
    log "patched CSS .tab .name -> ${TAB_FONT_SIZE}px"
    CHANGED=1
  else
    log "ERROR: CSS patch step failed"
    exit 0
  fi
else
  log "CSS already patched — skipping"
fi

# --- patch CSS: left sidebar badge icon size override ----------------------
# Wave's VTab TabBadges className includes [&_i]:text-[10px], which forces
# the badge icon (spinner/check/bell) to 10px — nearly invisible at that
# size. We append a CSS rule that overrides it using the vtab marker class
# as a selector.
# The marker class (wave-tab-font-patch-vtab-<N>px) is on every VTab item,
# so this targets only left-sidebar tabs, not the top tab bar. Appended to
# the end of the CSS file so it wins the cascade over the [&_i]:text-[10px]
# rule (same specificity 0,1,1 — later wins).
BADGE_CSS_MARKER="/* wave-tab-font-patch:badge-icon-${VTAB_BADGE_ICON_SIZE}px */"
if ! grep -qF "$BADGE_CSS_MARKER" "$CSS_FILE"; then
  cat >> "$CSS_FILE" <<CSS
.wave-tab-font-patch-vtab-${VTAB_FONT_SIZE}px i{font-size:${VTAB_BADGE_ICON_SIZE}px!important}${BADGE_CSS_MARKER}
CSS
  log "patched CSS vtab badge icon -> ${VTAB_BADGE_ICON_SIZE}px"
  CHANGED=1
else
  log "CSS badge icon already patched — skipping"
fi

# --- patch JS: left sidebar VTabBar item (text-xs -> larger class) ---------
# The vertical tab bar (app:tabbar = "left") renders each tab as a div with
# Tailwind classes including `text-xs` (12px). The label child inherits it.
# We replace `text-xs` with a larger standard class in that exact className
# string and append a marker class for idempotency. The marker class is an
# unknown Tailwind class — harmless, just a detection tag.
if [[ $JS_DONE -eq 0 ]]; then
  if python3 - "$JS_FILE" "$VTAB_TW_CLASS" "$VTAB_MARKER_CLASS" <<'PY'
import sys
path, tw_class, marker_class = sys.argv[1], sys.argv[2], sys.argv[3]
# The exact VTabBar item className string (unique in the JS bundle).
old = "group relative flex h-9 w-full shrink-0 cursor-pointer items-center pl-3 text-xs transition-colors select-none"
new = old.replace(" text-xs ", f" {tw_class} ") + " " + marker_class
js = open(path).read()
n = js.count(old)
if n != 1:
    print(f'ERROR: expected 1 match of vtab className, found {n}', file=sys.stderr)
    sys.exit(1)
open(path, 'w').write(js.replace(old, new, 1))
print(f"patched vtab className: text-xs -> {tw_class} (+ marker {marker_class})")
PY
  then
    log "patched JS vtab className: text-xs -> $VTAB_TW_CLASS"
    CHANGED=1
  else
    log "ERROR: JS vtab patch step failed"
    exit 0
  fi
else
  log "JS vtab already patched — skipping"
fi

if [[ $CHANGED -eq 0 ]]; then
  log "no changes needed — no-op"
  exit 0
fi

# --- repack ----------------------------------------------------------------
# Repack with --unpack for native binaries & schema files that must stay on
# disk (matches Wave's original build config). The --unpack glob is evaluated
# relative to cwd, so we cd into the extracted tree first.
log "repacking asar"
( cd "$WORK_DIR/extracted" && \
  "${ASAR_BIN[@]}" pack . "$WORK_DIR/app.asar.new" \
    --unpack "{dist/bin/*,dist/schema/*}" ) 2>/dev/null

if [[ ! -f "$WORK_DIR/app.asar.new" ]]; then
  log "ERROR: repack produced no asar — aborting"
  exit 0
fi

# Sanity: markers must be present in the repacked asar.
"${ASAR_BIN[@]}" extract "$WORK_DIR/app.asar.new" "$WORK_DIR/verify" 2>/dev/null
VERIFY_CSS="$WORK_DIR/verify/dist/frontend/assets/$(basename "$CSS_REL")"
VERIFY_JS="$WORK_DIR/verify/dist/frontend/assets/$JS_BASENAME"
if [[ $CSS_DONE -eq 0 ]] && ! grep -qF "$CSS_MARKER" "$VERIFY_CSS"; then
  log "ERROR: repacked asar missing CSS marker — aborting without replacing"
  exit 0
fi
if [[ $JS_DONE -eq 0 ]] && ! grep -qF "$VTAB_MARKER_CLASS" "$VERIFY_JS"; then
  log "ERROR: repacked asar missing JS vtab marker — aborting without replacing"
  exit 0
fi
if ! grep -qF "$BADGE_CSS_MARKER" "$VERIFY_CSS"; then
  log "ERROR: repacked asar missing badge icon CSS marker — aborting without replacing"
  exit 0
fi

# --- replace ---------------------------------------------------------------
# Use `cp` (not `mv`) so this works even while Wave is running. `mv` (rename)
# fails with "Operation not permitted" because the running Wave has the asar
# memory-mapped. `cp` opens-truncates-writes, which macOS allows; the running
# Wave keeps its stale memory mapping and is unaffected. The next Wave launch
# picks up the patched content.
log "replacing asar (cp)"
cp "$WORK_DIR/app.asar.new" "$ASAR"
log "patched: top tabs=${TAB_FONT_SIZE}px, vtab=${VTAB_FONT_SIZE}px ($VTAB_TW_CLASS), badge icon=${VTAB_BADGE_ICON_SIZE}px; takes effect on next Wave launch"
