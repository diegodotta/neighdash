#!/usr/bin/env bash
# Run the site on this computer, exactly as Cloudflare will serve it, and open it.
#
#   preview.sh [site-dir]        (defaults: PORT=8787, NO_OPEN=1 to skip the browser)
#
# Uses `wrangler dev`, Cloudflare's own router, so _redirects, _headers, the Worker
# and the 404 page behave as they will live. A plain file server
# (`python3 -m http.server`) ignores all of that and makes redirects look broken, or
# fine when they aren't (traps.md 33). Pages that load templates/preview-banner.js
# show a yellow "Preview on your computer" bar, so nobody mistakes this for the
# real site. Leave it running while testing, Ctrl+C stops it.
set -euo pipefail
DIR="${1:-.}"; cd "$DIR"
PORT="${PORT:-8787}"
URL="http://localhost:$PORT/"

CONF=""; for c in wrangler.jsonc wrangler.json; do [ -f "$c" ] && CONF="$c" && break; done
[ -n "$CONF" ] || { echo "No wrangler.jsonc here. Run this from the site's folder."; exit 1; }
ASSETS=$(python3 - "$CONF" <<'PY'
import json, re, sys
t = open(sys.argv[1]).read()
t = re.sub(r'(?m)^\s*//.*$', "", t)
t = re.sub(r'(?<=[,{\[\s])//[^\n"]*$', "", t, flags=re.M)
t = re.sub(r",(\s*[}\]])", r"\1", t)
print(json.loads(t).get("assets", {}).get("directory", "."))
PY
)
[ -d "$ASSETS" ] || { echo "The site's folder ($ASSETS) doesn't exist yet. Build the site first."; exit 1; }
grep -rlq "preview-banner.js" "$ASSETS" --include='*.html' 2>/dev/null \
  || echo "Note: the pages don't load preview-banner.js, so there will be no preview bar (templates/preview-banner.js)."

NAME=$(basename "$(pwd)")
STATE="${XDG_CACHE_HOME:-$HOME/.cache}/neighdash/wrangler-state/$NAME"   # outside the repo (traps.md 24)
mkdir -p "$STATE"
if curl -s -o /dev/null --max-time 2 "$URL"; then echo "Something is already running on port $PORT. Try PORT=8788 $0"; exit 1; fi

echo "Starting the preview (the first run downloads Cloudflare's tools, give it a minute)..."
npx -y wrangler dev --port "$PORT" --inspector-port $((PORT + 1000)) --persist-to "$STATE" > "$STATE/dev.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT INT TERM
for _ in $(seq 1 120); do
  curl -s -o /dev/null --max-time 2 "$URL" && break
  kill -0 "$PID" 2>/dev/null || { echo "The preview didn't start. Last lines of the log:"; tail -20 "$STATE/dev.log"; exit 1; }
  sleep 1
done

cat <<MSG

  Your site is running on this computer only:  $URL

  Nobody else can see it, and your real site hasn't changed. The yellow bar at
  the top of each page is the reminder. Click around, check the pages you care
  about, and compare them with the real site in another tab.

  Press Ctrl+C here to stop the preview.

MSG
if [ -z "${NO_OPEN:-}" ]; then
  if command -v open >/dev/null; then open "$URL"; elif command -v xdg-open >/dev/null; then xdg-open "$URL" >/dev/null 2>&1 || true; fi
fi
wait "$PID"
