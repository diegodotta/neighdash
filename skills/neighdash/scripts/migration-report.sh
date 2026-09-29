#!/usr/bin/env bash
# Generate MIGRATION-REPORT.md for a site: before/after Lighthouse, page weight,
# and a modelled energy/carbon comparison.
#
# CAPTURE THE "BEFORE" RUN *BEFORE* YOU CUT OVER. Once DNS points at the Worker
# the old site is only reachable by pinning the origin IP, and once the hosting
# plan is cancelled it is gone for good.
#
# Runs from the site's folder. Raw runs go to ./.neighdash/reports/<domain>/ (add
# it to .gitignore), the report to ./MIGRATION-REPORT.md.
#
#   # 1. BEFORE cutover (old site still live on its own domain):
#   scripts/migration-report.sh <domain> --before https://<domain>/
#
#   # 1b. AFTER cutover, if you forgot: pin the old origin IP. Chrome's
#   #     --host-resolver-rules value contains spaces, so it MUST go on a
#   #     separately-launched Chrome, passing it inside lighthouse's
#   #     --chrome-flags silently splits it and audits the NEW site instead.
#   scripts/migration-report.sh <domain> --before-origin <origin-ip>
#
#   # 2. AFTER deploy:
#   scripts/migration-report.sh <domain> --after https://<domain>/
#
#   # 3. Write the report from the two saved runs:
#   scripts/migration-report.sh <domain> --report
#
# Energy/carbon uses @tgwf/co2 (Sustainable Web Design Model v4), the same
# model behind websitecarbon.com, plus a Green Web Foundation hosting lookup.
# These are MODELLED ESTIMATES from bytes transferred, not measurements.
set -euo pipefail

DOMAIN="${1:?usage: migration-report.sh <domain> [--before <url>|--before-origin <ip>|--after <url>|--report]}"
MODE="${2:---report}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${NEIGHDASH_REPORTS:-$PWD/.neighdash/reports}/$DOMAIN"
OUTFILE="${REPORT_OUT:-$PWD/MIGRATION-REPORT.md}"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/neighdash"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[ -x "$CHROME" ] || CHROME="$(command -v google-chrome || command -v chromium || echo "$CHROME")"
mkdir -p "$DATA"

# Single Lighthouse runs vary a LOT, a one-off comparison reported FCP as "+63%
# worse" purely as sampling noise. Always run several and keep the median.
RUNS="${RUNS:-3}"

pick_median() { # pick_median <dir> <prefix> <dest>
  python3 - "$1" "$2" "$3" <<'PY'
import json, pathlib, shutil, sys
d, prefix, dest = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
runs = sorted(d.glob(f"{prefix}*.json"))
scored = []
for p in runs:
    try: scored.append((json.loads(p.read_text())["categories"]["performance"]["score"], p))
    except Exception: pass
scored.sort(key=lambda t: t[0])
chosen = scored[len(scored) // 2][1]
shutil.copy(chosen, dest)
spread = [round(s * 100) for s, _ in scored]
# Keep the spread: run-to-run variance is a reliability signal in its own right.
pathlib.Path(str(dest) + ".runs").write_text(json.dumps(spread))
print(f"  runs: {spread} → median {round(scored[len(scored)//2][0]*100)} ({chosen.name})")
for p in runs: p.unlink()
PY
}

lh() { # lh <url> <outfile> [extra chrome flags]
  npx -y lighthouse@12 "$1" \
    --only-categories=performance,accessibility,best-practices,seo \
    --form-factor=mobile --screenEmulation.mobile \
    --output=json --output-path="$2" --quiet \
    --chrome-flags="--headless --disable-gpu --no-sandbox ${3:-}" >/dev/null 2>&1
}

case "$MODE" in
  --before)
    URL="${3:?need a url}"; echo "auditing BEFORE: $URL ($RUNS runs)"
    curl -s -o /dev/null --max-time 60 "$URL" || true
    for i in $(seq 1 "$RUNS"); do lh "$URL" "$DATA/_b$i.json"; done
    pick_median "$DATA" "_b" "$DATA/before.json"; echo "saved $DATA/before.json" ;;

  --before-origin)
    IP="${3:?need the origin ip}"
    echo "auditing BEFORE via origin $IP (bypasses the CDN, best case for the old site)"
    PROFILE="$(mktemp -d)"
    "$CHROME" \
      --headless --disable-gpu --no-sandbox --remote-debugging-port=9222 \
      --user-data-dir="$PROFILE" --ignore-certificate-errors \
      --host-resolver-rules="MAP $DOMAIN $IP" about:blank >/dev/null 2>&1 &
    CHROME=$!
    until curl -s --max-time 3 http://localhost:9222/json/version >/dev/null 2>&1; do sleep 1; done
    for i in $(seq 1 "$RUNS"); do
      npx -y lighthouse@12 "https://$DOMAIN/" --port=9222 \
        --only-categories=performance,accessibility,best-practices,seo \
        --form-factor=mobile --screenEmulation.mobile \
        --output=json --output-path="$DATA/_b$i.json" --quiet >/dev/null 2>&1
    done
    pick_median "$DATA" "_b" "$DATA/before.json"
    # Give Chrome a moment to flush its profile before removing it, or the
    # rm races with it and errors "Directory not empty".
    kill "$CHROME" 2>/dev/null || true
    wait "$CHROME" 2>/dev/null || true
    rm -rf "$PROFILE" 2>/dev/null || true
    # Guard against the silent-failure mode: if no origin-specific markers are
    # present we probably audited the NEW site.
    python3 -c "
import json,sys
o=json.load(open('$DATA/before.json'))
u=[i['url'] for i in o['audits']['network-requests']['details']['items']]
print('captured', len(u), 'requests')
if not any(('wp-content' in x or 'wp-includes' in x) for x in u):
    print('WARNING: no WordPress markers, did the host mapping apply? Verify before trusting this.', file=sys.stderr)
"
    echo "saved $DATA/before.json" ;;

  --after)
    URL="${3:-https://$DOMAIN/}"; echo "auditing AFTER: $URL ($RUNS runs)"
    # Warm the edge first, auditing a cold cache tanks LCP/FCP and looks like a regression.
    for _ in 1 2; do curl -s -o /dev/null --max-time 60 "$URL" || true; done
    for i in $(seq 1 "$RUNS"); do lh "$URL" "$DATA/_a$i.json"; done
    pick_median "$DATA" "_a" "$DATA/after.json"; echo "saved $DATA/after.json" ;;

  --report)
    [ -f "$DATA/before.json" ] && [ -f "$DATA/after.json" ] || {
      echo "need both $DATA/before.json and $DATA/after.json" >&2; exit 1; }
    mkdir -p "$CACHE"
    [ -d "$CACHE/node_modules/@tgwf/co2" ] || npm install --prefix "$CACHE" --silent --no-fund --no-audit @tgwf/co2@0.19.0 >/dev/null 2>&1
    NODE_PATH="$CACHE/node_modules" node "$HERE/lib/report.js" "$DATA/before.json" "$DATA/after.json" "$DOMAIN" > "$OUTFILE"
    echo "wrote $OUTFILE" ;;

  *) echo "unknown mode: $MODE" >&2; exit 1 ;;
esac
