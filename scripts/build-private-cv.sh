#!/usr/bin/env bash
# Build private PDF CVs (with phone number) into pdfCvs/ — never published.
#
# Private values live in _config.private.yml (git-ignored), e.g.:
#   author:
#     phone: "+48 000 000 000"
#
# Usage:  bash scripts/build-private-cv.sh [version]   (default version: v3)
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-v3}"
YEAR="$(date +%Y)"
OUT_DIR="pdfCvs"
BUILD_DIR=".private-build"          # dot-dir: ignored by Jekyll and git
PORT=4010

[ -f _config.private.yml ] || { echo "Missing _config.private.yml (see header of this script)"; exit 1; }

# Find a Chromium-based browser (Chrome or Edge).
BROWSER="${BROWSER:-}"
for c in \
  "/c/Program Files/Google/Chrome/Application/chrome.exe" \
  "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
  "$(command -v google-chrome || true)" "$(command -v chromium || true)"; do
  [ -z "$BROWSER" ] && [ -n "$c" ] && [ -x "$c" ] && BROWSER="$c"
done
[ -n "$BROWSER" ] || { echo "No Chrome/Edge found; set BROWSER=/path/to/chrome"; exit 1; }

# _config.yml keeps the public url/baseurl, so the PDFs link to the live site.
bundle exec jekyll build -q --config _config.yml,_config.private.yml -d "$BUILD_DIR/resume-template"

python -m http.server "$PORT" --directory "$BUILD_DIR" >/dev/null 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
sleep 2

mkdir -p "$OUT_DIR"
# Fresh browser profile each run, so a cached main.css from an earlier run is never used.
PROFILE_DIR="$BUILD_DIR/browser-profile"
rm -rf "$PROFILE_DIR"
for pair in "EN:/" "PL:/pl/"; do
  lang="${pair%%:*}"; path="${pair#*:}"
  out="$OUT_DIR/CV_${lang}_${YEAR}_${VERSION}.pdf"
  "$BROWSER" --headless=new --disable-gpu --no-pdf-header-footer --virtual-time-budget=5000 \
    --user-data-dir="$PWD/$PROFILE_DIR" \
    --print-to-pdf="$PWD/$BUILD_DIR/tmp.pdf" "http://localhost:$PORT/resume-template$path?print" 2>/dev/null
  # Render to a temp file first: the browser fails silently if $out is open (locked) in a PDF viewer.
  [ -s "$BUILD_DIR/tmp.pdf" ] || { echo "PDF render failed for $lang"; exit 1; }
  mv -f "$BUILD_DIR/tmp.pdf" "$out" || { echo "Cannot overwrite $out - close it in your PDF viewer and re-run"; exit 1; }
  echo "wrote $out"
done
