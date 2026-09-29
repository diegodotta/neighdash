#!/usr/bin/env bash
# Route matrix: every URL the old site answered, and what the new one must answer.
# The only test that exercises Cloudflare's real router (run_worker_first, _redirects,
# not_found_handling). Unit tests of the Worker can't catch a routing bug (traps.md 3).
#
#   route-check.sh routes.txt http://127.0.0.1:8787      # against `npx wrangler dev`
#   route-check.sh routes.txt https://example.com        # against the live site
#
# routes.txt, one check per line:   <path or full URL>  <status>  [expect]
#   expect = the end of the Location header (redirects) or part of the Content-Type
#   A full URL ignores the base (use it for www checks against the live site only).
#   Lines starting with # are comments. Lines starting with "live " run only when the
#   base is https://.
#
#   /                                         200
#   /feed/                                    200  application/rss+xml
#   /?p=123                                   301  /some-post/
#   /wp-content/uploads/2024/01/cat.jpg       301  /wp-content/uploads/2024/01/cat.webp
#   /.git/config                              404
#   live https://www.example.com/about/?x=1   301  https://example.com/about/?x=1
set -uo pipefail
set -f   # no globbing: paths may contain * or ?
FILE="${1:?usage: route-check.sh <routes.txt> [base-url]}"
B="${2:-http://127.0.0.1:8787}"; B="${B%/}"
pass=0; fail=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"; [ -z "${line// }" ] && continue
  set -- $line
  if [ "$1" = "live" ]; then [[ "$B" == https://* ]] || continue; shift; fi
  path="$1"; want="$2"; expect="${3:-}"
  url="$path"; [[ "$path" == http* ]] || url="$B$path"
  out=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url} %{content_type}' --max-time 20 "$url")
  code=${out%% *}; rest=${out#* }; loc=${rest%% *}; ctype=${rest#* }
  if [ "$code" = "$want" ] && { [ -z "$expect" ] || [[ "$loc" == *"$expect" ]] || [[ "$ctype" == *"$expect"* ]]; }; then
    pass=$((pass+1))
  else
    fail=$((fail+1)); printf '✗ %-56s got %s %s %s (want %s %s)\n' "$path" "$code" "$loc" "$ctype" "$want" "$expect"
  fi
done < "$FILE"
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
