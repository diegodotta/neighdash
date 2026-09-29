#!/usr/bin/env bash
# Post-deploy QA for a migrated static site.
# Usage: qa-check.sh https://example.com [/extra/path ...]
# Optional: PSI_API_KEY=... for a PageSpeed Insights score.
set -uo pipefail
BASE="${1:?usage: qa-check.sh <base-url> [extra paths...]}"; shift || true
BASE="${BASE%/}"
pass=0; fail=0
code(){ curl -s -o /dev/null -w '%{http_code}' "$1?cb=$RANDOM"; }        # cache-busted
ok(){   printf "  \033[32mPASS\033[0m %s\n" "$1"; pass=$((pass+1)); }
no(){   printf "  \033[31mFAIL\033[0m %s\n" "$1"; fail=$((fail+1)); }

echo "QA: $BASE"

echo "[ reachable ]"
[ "$(code "$BASE/")" = 200 ] && ok "homepage 200" || no "homepage not 200"
for p in "$@"; do
  [ "$(code "$BASE$p")" = 200 ] && ok "$p 200" || no "$p not 200"
done

echo "[ nothing leaked ]"
for p in /.git/config /.git/HEAD /.wrangler/ /wrangler.jsonc /README.md /.gitignore /.env /.dev.vars /MIGRATION-REPORT.md; do
  [ "$(code "$BASE$p")" = 404 ] && ok "$p → 404" || no "$p is served (should be 404)"
done

echo "[ custom 404 ]"
[ "$(code "$BASE/definitely-not-a-page-$RANDOM")" = 404 ] && ok "unknown path → 404" || no "no 404 handling"

echo "[ OpenGraph ]"
html="$(curl -s "$BASE/")"
grep -qi 'property="og:title"' <<<"$html" && ok "og:title present" || no "og:title missing"
ogimg="$(grep -io 'property="og:image"[^>]*content="[^"]*"' <<<"$html" | grep -io 'content="[^"]*"' | head -1 | sed 's/content="//;s/"//')"
if [ -n "$ogimg" ]; then
  [ "$(code "$ogimg")" = 200 ] && ok "og:image resolves ($ogimg)" || no "og:image does NOT resolve ($ogimg)"
else no "og:image missing"; fi
grep -qi 'twitter:card' <<<"$html" && ok "twitter:card present" || no "twitter:card missing"

echo "[ analytics ]"
if grep -qiE 'gtag\(|googletagmanager|static\.cloudflareinsights\.com|plausible|umami' <<<"$html"; then
  ok "analytics snippet present"
else no "no analytics snippet found (GA4 or Cloudflare Web Analytics)"; fi

echo "[ performance ]"
if [ -n "${PSI_API_KEY:-}" ]; then
  score="$(curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=$BASE/&strategy=mobile&key=$PSI_API_KEY" \
    | grep -o '"score":[0-9.]*' | head -1 | cut -d: -f2)"
  [ -n "$score" ] && echo "  PSI mobile performance score: $score (1.0 = 100)"
else
  echo "  (set PSI_API_KEY for an automatic score) manual: https://pagespeed.web.dev/analysis?url=$BASE/"
fi

echo "---- $pass passed, $fail failed ----"
[ "$fail" = 0 ]
