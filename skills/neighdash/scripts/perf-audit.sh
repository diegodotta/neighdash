#!/usr/bin/env bash
# Local Lighthouse audit: scores, Core Web Vitals, and every failing audit.
#
# Why this exists: qa-check.sh can call the PageSpeed Insights API, but the
# anonymous quota is shared and WILL run out ("Quota exceeded ... Queries per
# day"), which is exactly what happened mid-migration. Running Lighthouse
# locally has no quota and gives the same audits.
#
# Usage:
#   perf-audit.sh https://example.com              # mobile (default)
#   perf-audit.sh https://example.com desktop
#   RUNS=3 perf-audit.sh https://example.com       # median of 3
set -euo pipefail

URL="${1:?usage: perf-audit.sh <url> [mobile|desktop]}"
FORM="${2:-mobile}"
RUNS="${RUNS:-1}"
OUT="$(mktemp -d)"

if [ "$FORM" = "desktop" ]; then
  EMU=(--preset=desktop)
else
  EMU=(--form-factor=mobile --screenEmulation.mobile)
fi

# IMPORTANT: warm the edge cache first. Auditing straight after a cache purge
# measures every asset as a cold MISS and tanks LCP/FCP/Speed Index, it once
# showed LCP 1.6s -> 4.2s purely as an artefact. Warm, then measure.
echo "warming cache: $URL"
for _ in 1 2; do curl -s -o /dev/null --max-time 30 "$URL" || true; done

for i in $(seq 1 "$RUNS"); do
  echo "lighthouse run $i/$RUNS ($FORM)..."
  npx -y lighthouse@12 "$URL" \
    --only-categories=performance,accessibility,best-practices,seo \
    "${EMU[@]}" --output=json --output-path="$OUT/run$i.json" --quiet \
    --chrome-flags="--headless --disable-gpu --no-sandbox" >/dev/null 2>&1
done

python3 - "$OUT" "$RUNS" "$URL" <<'PY'
import json, sys, pathlib, statistics
out, runs, url = pathlib.Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
reports = [json.loads((out / f"run{i}.json").read_text()) for i in range(1, runs + 1)]

G, Y, R, B, N = "\033[32m", "\033[33m", "\033[31m", "\033[1m", "\033[0m"
def tint(v):  # lighthouse thresholds
    return G if v >= 90 else (Y if v >= 50 else R)

print(f"\n{B}PERF: {url}{N}")
print(f"[ scores ]{'  (median of %d runs)' % runs if runs > 1 else ''}")
for k in ["performance", "accessibility", "best-practices", "seo"]:
    vals = [round(r["categories"][k]["score"] * 100) for r in reports]
    v = round(statistics.median(vals))
    spread = f"   runs: {vals}" if runs > 1 and len(set(vals)) > 1 else ""
    print(f"  {tint(v)}{v:>3}{N}  {k}{spread}")

# Everything below reports the SAME run, the one whose performance score is the
# median. Mixing runs produces contradictions (a 1.6s LCP printed next to a
# 3610ms render delay borrowed from a slower run).
perf = [r["categories"]["performance"]["score"] for r in reports]
med = sorted(range(len(perf)), key=lambda i: perf[i])[len(perf) // 2]
rep = reports[med]
if runs > 1:
    print(f"[ detail below is from run {med + 1}, the median ]")

print("[ core web vitals ]")
for m in ["first-contentful-paint", "largest-contentful-paint",
          "total-blocking-time", "cumulative-layout-shift", "speed-index"]:
    a = rep["audits"][m]
    print(f"  {tint(a['score']*100)}{a['displayValue']:>9}{N}  {m}")

# LCP phase breakdown: tells you whether it's the network or the main thread.
lcp = rep["audits"].get("largest-contentful-paint-element", {})
for group in (lcp.get("details", {}).get("items") or []):
    for it in (group.get("items") or []):
        if "phase" in it:
            print(f"      {it['phase']}: {round(it['timing'])}ms")

print("[ failing audits ]")
last = rep["audits"]
fails = [(a["score"], k, a["title"]) for k, a in last.items()
         if a.get("score") is not None and a["score"] < 1
         and a.get("scoreDisplayMode") != "informative"]
if not fails:
    print(f"  {G}none{N}")
for score, key, title in sorted(fails):
    c = R if score < 0.5 else Y
    print(f"  {c}[{score:.2f}]{N} {key}: {title}")

    det = (last[key].get("details") or {}).get("items") or []
    for item in det[:3]:
        u = item.get("url", "")
        if u:
            u = u.replace(url.rstrip("/"), "").replace("https://", "")
            waste = item.get("wastedBytes")
            extra = f"  (−{round(waste/1024)}KB)" if waste else ""
            print(f"        {u[:78]}{extra}")
print()
PY

echo "raw reports: $OUT"
