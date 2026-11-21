#!/usr/bin/env bash
# Build private PDF CVs (with phone number) into pdfCvs/ — never published.
#
# Private values live in _config.private.yml (git-ignored), e.g.:
#   author:
#     phone: "+48 000 000 000"
#
# Optional, also in _config.private.yml: a folder that always receives a copy of the final PDFs
#   pdf_copy_dir: "C:/path/to/CV_folder"
#
# Usage:  bash scripts/build-private-cv.sh [--archive]
#   Writes the current CV as pdfCvs/CV_<LANG>_<YEAR>.pdf (no version suffix) and copies it to pdf_copy_dir.
#   --archive  first keeps the existing current PDFs as older versions, CV_<LANG>_<YEAR>_v<N>.pdf
#              (N = highest existing version + 1): in pdfCvs/archive/ and directly inside pdf_copy_dir.
#              Without it, the current PDFs are overwritten.
set -euo pipefail

cd "$(dirname "$0")/.."
ARCHIVE=false
[ "${1:-}" = "--archive" ] && ARCHIVE=true
YEAR="$(date +%Y)"
OUT_DIR="pdfCvs"
ARCHIVE_DIR="$OUT_DIR/archive"
COPY_DIR="$(sed -n 's/^pdf_copy_dir:[[:space:]]*"\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' _config.private.yml 2>/dev/null || true)"
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

# archive_current <current.pdf> <archive dir>: move current to <archive dir>/<name>_v<max+1>.pdf
archive_current() {
  local cur="$1" dir="$2" base n=0 f v
  [ -f "$cur" ] || return 0
  base="$(basename "$cur" .pdf)"
  mkdir -p "$dir"
  for f in "$dir/${base}"_v*.pdf; do
    [ -e "$f" ] || continue
    v="${f##*_v}"; v="${v%.pdf}"
    [ "$v" -gt "$n" ] 2>/dev/null && n="$v"
  done
  mv "$cur" "$dir/${base}_v$((n + 1)).pdf"     || { echo "Cannot archive $cur - close it in your PDF viewer and re-run"; exit 1; }
  echo "archived $cur -> $dir/${base}_v$((n + 1)).pdf"
}

mkdir -p "$OUT_DIR"
# Fresh browser profile each run, so a cached main.css from an earlier run is never used.
PROFILE_DIR="$BUILD_DIR/browser-profile"
rm -rf "$PROFILE_DIR"
for pair in "EN:/" "PL:/pl/"; do
  lang="${pair%%:*}"; path="${pair#*:}"
  name="CV_${lang}_${YEAR}.pdf"
  out="$OUT_DIR/$name"
  "$BROWSER" --headless=new --disable-gpu --no-pdf-header-footer --virtual-time-budget=5000     --user-data-dir="$PWD/$PROFILE_DIR"     --print-to-pdf="$PWD/$BUILD_DIR/tmp.pdf" "http://localhost:$PORT/resume-template$path?print" 2>/dev/null
  # Render to a temp file first: the browser fails silently if $out is open (locked) in a PDF viewer.
  [ -s "$BUILD_DIR/tmp.pdf" ] || { echo "PDF render failed for $lang"; exit 1; }
  if $ARCHIVE; then
    archive_current "$out" "$ARCHIVE_DIR"
    [ -n "$COPY_DIR" ] && archive_current "$COPY_DIR/$name" "$COPY_DIR"
  fi
  mv -f "$BUILD_DIR/tmp.pdf" "$out" || { echo "Cannot overwrite $out - close it in your PDF viewer and re-run"; exit 1; }
  echo "wrote $out"
  if [ -n "$COPY_DIR" ]; then
    mkdir -p "$COPY_DIR"
    cp -f "$out" "$COPY_DIR/$name" || { echo "Cannot copy to $COPY_DIR/$name - close it in your PDF viewer and re-run"; exit 1; }
    echo "copied to $COPY_DIR/$name"
  fi
done
