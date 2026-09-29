#!/usr/bin/env bash
# Screenshot every page of two copies of a static site and count differing pixels.
# For refactors that must not change how pages look (traps.md 11). Run a control
# first (baseline vs an identical copy) to learn the noise floor.
#
#   pixel-diff.sh <baseline-dir> <new-dir> <out-dir> [widths...]   (default 480 1440)
#
# Needs Chrome and ImageMagick (`magick`). CHROME=... to point at another browser,
# SKIP='^/games/' to leave out paths matching a regex, BLOCK='MAP ads.example 127.0.0.1'
# to silence more third parties.
set -u
A_DIR="$1"; B_DIR="$2"; D="$3"; shift 3
WIDTHS=("${@:-480 1440}")
[ $# -eq 0 ] && WIDTHS=(480 1440)
C="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
rm -rf "$D"; mkdir -p "$D/a" "$D/b" "$D/d"
(cd "$A_DIR" && exec python3 -m http.server 8811 >/dev/null 2>&1) & PA=$!
(cd "$B_DIR" && exec python3 -m http.server 8812 >/dev/null 2>&1) & PB=$!
trap 'kill $PA $PB 2>/dev/null' EXIT
sleep 1
# Third parties are mapped to localhost: they render nothing and only add noise.
RULES="MAP www.googletagmanager.com 127.0.0.1, MAP connect.facebook.net 127.0.0.1${BLOCK:+, $BLOCK}"
shot() { "$C" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
  --window-size="$3",7000 --virtual-time-budget=12000 --host-resolver-rules="$RULES" \
  --screenshot="$2" "$1" >/dev/null 2>&1; }
PAGES=()
while IFS= read -r line; do PAGES+=("$line"); done < <(cd "$B_DIR" && find . -name index.html | sed 's#^\.##; s#index.html$##' | { if [ -n "${SKIP:-}" ]; then grep -Ev "$SKIP"; else cat; fi; } | sort; echo /404.html)
for p in "${PAGES[@]}"; do
  n=$(echo "$p" | sed -E 's#^/##; s#/$##; s#[/.]#_#g'); n=${n:-home}
  for w in "${WIDTHS[@]}"; do
    shot "http://127.0.0.1:8811$p" "$D/a/${n}_$w.png" "$w"
    shot "http://127.0.0.1:8812$p" "$D/b/${n}_$w.png" "$w"
    ae=$(magick compare -metric AE "$D/a/${n}_$w.png" "$D/b/${n}_$w.png" "$D/d/${n}_$w.png" 2>&1 | awk '{print $1}')
    printf "%-44s %5s  %s\n" "$p" "$w" "$ae"
  done
done | tee "$D/result.txt"
echo "--- compared: $(wc -l < "$D/result.txt" | tr -d ' '), identical: $(awk '$3=="0"' "$D/result.txt" | wc -l | tr -d ' ')"
