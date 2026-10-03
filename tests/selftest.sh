#!/usr/bin/env bash
# NeighDash self-test: run after changing anything in skills/neighdash/.
#
#   tests/selftest.sh            # offline checks + the Worker template on wrangler dev
#   ONLINE=1 tests/selftest.sh   # also routes-from-sitemap.py against a real site
#
# Needs bash, python3, node/npx (wrangler is downloaded on first run) and curl.
# Everything happens in a temporary folder, on ports 8799, 8800 and 8801.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SK="$ROOT/skills/neighdash"
T="$(mktemp -d)"
PORT=8799
pass=0; fail=0
# The oldest Python NeighDash supports is 3.9, the one macOS ships. Run the Python
# scripts under it when it's here, or a newer python3 hides 3.10-only syntax.
OLDPY=python3
for c in /usr/bin/python3 python3.9; do
  if command -v "$c" >/dev/null && "$c" -c 'import sys; sys.exit(sys.version_info[:2] != (3, 9))' 2>/dev/null; then OLDPY="$c"; break; fi
done
ok(){ printf "  \033[32mPASS\033[0m %s\n" "$1"; pass=$((pass+1)); }
no(){ printf "  \033[31mFAIL\033[0m %s\n" "$1"; fail=$((fail+1)); }
check(){ local name="$1"; shift; if "$@" >"$T/last.log" 2>&1; then ok "$name"; else no "$name"; sed 's/^/       /' "$T/last.log" | tail -8; fi; }
refuse(){ local name="$1"; shift; if "$@" >"$T/last.log" 2>&1; then no "$name (should have failed)"; else ok "$name"; fi; }
WPID=""; EPID=""
cleanup(){ [ -n "$WPID" ] && kill "$WPID" 2>/dev/null; [ -n "$EPID" ] && kill "$EPID" 2>/dev/null; pkill -f "wrangler dev.*--port $PORT" 2>/dev/null; rm -rf "$T"; }
trap cleanup EXIT

echo "[ syntax ]"
for f in "$SK"/scripts/*.sh; do check "bash -n $(basename "$f")" bash -n "$f"; done
for f in "$SK"/scripts/*.py; do check "python $(basename "$f")" python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f"; done
for f in "$SK"/scripts/lib/*.js "$SK"/templates/worker/*.js "$SK"/templates/preview-banner.js "$SK"/templates/neighdash-admin.js; do check "node --check $(basename "$f")" node --check "$f"; done

echo "[ plugin ]"
if command -v claude >/dev/null; then check "claude plugin validate --strict" claude plugin validate "$ROOT" --strict; else echo "  skip claude plugin validate (claude not installed)"; fi

echo "[ scaffold and gates ]"
cd "$T"
check "new-site.sh scaffolds" "$SK/scripts/new-site.sh" example.com "$T"
check "scaffold loads the preview banner" grep -q 'preview-banner.js" defer data-live="example.com"' "$T/example.com/public/index.html"
check "scaffold ships preview-banner.js" test -f "$T/example.com/public/preview-banner.js"
check "safety-check passes on the scaffold" "$SK/scripts/safety-check.sh" "$T/example.com"
mkdir -p "$T/rootserve" && printf '{ "name": "x", "assets": { "directory": "./" } }\n' > "$T/rootserve/wrangler.jsonc"
refuse "safety-check refuses a repo-root site without .assetsignore" "$SK/scripts/safety-check.sh" "$T/rootserve"

# A fake migrated WordPress blog, served from dist/ with the legacy-redirect Worker.
B="$T/blog"; mkdir -p "$B/worker" "$B/dist/wp-content/uploads/2024/01" "$B/dist/hello-world" "$B/dist/feed" "$B/dist/tag/cats"
sed "s/SITE-NAME-HERE/selftest-blog/" "$SK/templates/wrangler.worker.jsonc" > "$B/wrangler.jsonc"
cp "$SK/templates/worker/legacy-redirects.js" "$B/worker/index.js"
cp "$SK/templates/assetsignore.template" "$B/dist/.assetsignore"
cp "$SK/templates/_headers" "$B/dist/_headers"
cp "$T/example.com/public/"{index.html,404.html,robots.txt,sitemap.xml,styles.css,preview-banner.js} "$B/dist/"
printf 'x' > "$B/dist/favicon.ico"
echo '<html><body>hello</body></html>' > "$B/dist/hello-world/index.html"
echo '<html><body>cats</body></html>' > "$B/dist/tag/cats/index.html"
echo '<?xml version="1.0"?><rss/>' > "$B/dist/feed/index.html"
printf 'RIFF' > "$B/dist/wp-content/uploads/2024/01/cat.webp"
echo '{"123": "/hello-world/"}' > "$B/dist/_wp-ids.json"
check "check-dist passes on a clean build" python3 "$SK/scripts/check-dist.py" "$B/dist"
check "check-dist runs on Python 3.9 ($OLDPY)" "$OLDPY" "$SK/scripts/check-dist.py" "$B/dist"
echo notes > "$B/dist/NOTES.md"
refuse "check-dist refuses Markdown in the build folder" python3 "$SK/scripts/check-dist.py" "$B/dist"
rm "$B/dist/NOTES.md"
echo '{}' > "$B/dist/neighdash-pages.json"
refuse "check-dist refuses a preview build (page map)" python3 "$SK/scripts/check-dist.py" "$B/dist"
rm "$B/dist/neighdash-pages.json"
cp "$B/dist/hello-world/index.html" "$T/hello.bak"
echo '<html><head><script src="/neighdash-admin.js" defer></script></head><body>hello</body></html>' > "$B/dist/hello-world/index.html"
refuse "check-dist refuses a page that loads the admin bar" python3 "$SK/scripts/check-dist.py" "$B/dist"
cp "$T/hello.bak" "$B/dist/hello-world/index.html"

echo "[ edit server, on $("$OLDPY" -V 2>&1) ]"
E="$T/md"; mkdir -p "$E/content/posts"
printf -- '---\ntitle: "Old post"\ndate: "2024-05-01 09:00:00"\n---\nHi.\n' > "$E/content/posts/old.md"
printf -- '---\ntitle: Idea\ndate: 2026-10-01\ndraft: true\n---\nSoon.\n' > "$E/content/posts/idea.md"
printf 'secret' > "$E/private.md"
printf '{ "edit": { "content": "content", "build": "touch built.flag", "port": 8801 } }\n' > "$E/neighdash.json"
mkdir -p "$E/dist" && printf '{ "name": "md", "assets": { "directory": "./dist" } }\n' > "$E/wrangler.jsonc"
"$OLDPY" "$SK/scripts/edit-server.py" "$E" --preview-port 8787 >"$T/edit.log" 2>&1 &
EPID=$!
for _ in $(seq 1 30); do curl -s -o /dev/null --max-time 1 http://127.0.0.1:8801/ && break; sleep 0.3; done
check "the edit server starts" kill -0 "$EPID"
O='Origin: http://localhost:8787'; X='X-NeighDash: 1'; EU=http://127.0.0.1:8801/__neighdash
post(){ curl -s -o /dev/null -w '%{http_code}' -X POST -H "Content-Type: application/json" "$@"; }
check "lists the drafts" sh -c "curl -s -H '$O' -H '$X' '$EU/state' | grep -q content/posts/idea.md"
check "refuses a request with no origin" test "$(curl -s -o /dev/null -w '%{http_code}' -H "$X" "$EU/state")" = 403
check "refuses another website" test "$(curl -s -o /dev/null -w '%{http_code}' -H 'Origin: https://evil.example' -H "$X" "$EU/state")" = 403
check "no CORS approval for another website" sh -c "! curl -s -D - -o /dev/null -X OPTIONS -H 'Origin: https://evil.example' '$EU/edit' | grep -qi access-control-allow-origin"
check "refuses a page from another preview (another port)" test "$(curl -s -o /dev/null -w '%{http_code}' -H 'Origin: http://localhost:8811' -H "$X" "$EU/state")" = 403
check "refuses DNS rebinding (foreign Host)" test "$(curl -s -o /dev/null -w '%{http_code}' -H 'Host: evil.example:8801' -H "$O" -H "$X" "$EU/state")" = 403
check "refuses without the custom header" test "$(post -H "$O" -d '{"file":"content/posts/idea.md","action":"publish"}' "$EU/edit")" = 403
check "refuses a file outside the content folder" test "$(post -H "$O" -H "$X" -d '{"file":"private.md","action":"publish"}' "$EU/edit")" = 403
check "refuses path traversal" test "$(post -H "$O" -H "$X" -d '{"file":"content/../private.md","action":"publish"}' "$EU/edit")" = 403
check "publishes a draft" test "$(post -H "$O" -H "$X" -d '{"file":"content/posts/idea.md","action":"publish"}' "$EU/edit")" = 200
check "publish removed draft: true" sh -c "! grep -q '^draft:' '$E/content/posts/idea.md'"
check "ran the build" test -f "$E/built.flag"
check "stamped the build for the bar" test -s "$E/dist/neighdash-build.txt"
refuse "check-dist refuses a build carrying the stamp" python3 "$SK/scripts/check-dist.py" "$E/dist"
check "unpublishes" test "$(post -H "$O" -H "$X" -d '{"file":"content/posts/old.md","action":"unpublish"}' "$EU/edit")" = 200
check "unpublish added draft: true" grep -q '^draft: true' "$E/content/posts/old.md"
check "re-dates, keeping the date's format" sh -c "test \"\$(curl -s -o /dev/null -w '%{http_code}' -X POST -H '$O' -H '$X' -d '{\"file\":\"content/posts/old.md\",\"action\":\"date\",\"date\":\"2024-06-02T10:15\"}' '$EU/edit')\" = 200 && grep -q '^date: \"2024-06-02 10:15:00\"' '$E/content/posts/old.md'"
kill "$EPID" 2>/dev/null

echo "[ the Worker template on Cloudflare's router (wrangler dev) ]"
cat > "$B/routes.txt" <<'EOF'
/                                              200
/hello-world/                                  200
/hello-world                                   307 /hello-world/
/feed/                                         200
/sitemap.xml                                   200
/wp-content/uploads/2024/01/cat.webp           200
/?s=kombi                                      302 /search/?q=kombi
/?p=123                                        301 /hello-world/
/wp-content/uploads/2024/01/cat.jpg            301 /wp-content/uploads/2024/01/cat.webp
/wp-content/uploads/2024/01/cat-1024x683.jpg   301 /wp-content/uploads/2024/01/cat.webp
/wp-content/uploads/2024/01/dog.jpg            404
/tag/cats/page/9/                              301 /tag/cats/
/page/2/                                       301 /
/hello-world/feed/                             301 /hello-world/
/comments/feed/                                301 /feed/
/sitemap_index.xml                             301 /sitemap.xml
/post-sitemap.xml                              301 /sitemap.xml
/wrangler.jsonc                                404
/worker/index.js                               404
/.git/config                                   404
/does-not-exist/                               404
EOF
start_dev(){  # start_dev [script]
  (cd "$B" && exec npx -y wrangler dev ${1:-} --port "$PORT" --inspector-port $((PORT + 1000)) --persist-to "$T/wr-state" >"$T/wrangler.log" 2>&1) &
  WPID=$!
  for _ in $(seq 1 120); do curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$PORT/" && return 0; kill -0 "$WPID" 2>/dev/null || break; sleep 1; done
  echo "wrangler dev didn't start:"; tail -15 "$T/wrangler.log"; return 1
}
stop_dev(){ kill "$WPID" 2>/dev/null; pkill -f "wrangler dev.*--port $PORT" 2>/dev/null; WPID=""; sleep 2; }
if start_dev; then
  check "every legacy route answers as planned" "$SK/scripts/route-check.sh" "$B/routes.txt" "http://127.0.0.1:$PORT"
  stop_dev
  cp "$SK/templates/worker/probe.js" "$B/worker/_probe.js"
  if start_dev worker/_probe.js; then
    hdr(){ curl -sI "http://127.0.0.1:$PORT$1" | grep -ic '^x-neighdash-worker'; }
    check "probe: homepage runs the Worker" test "$(hdr /)" = 1
    check "probe: old .jpg runs the Worker" test "$(hdr /wp-content/uploads/2024/01/cat.jpg)" = 1
    check "probe: a page is a plain asset" test "$(hdr /hello-world/)" = 0
    check "probe: a real image is a plain asset" test "$(hdr /wp-content/uploads/2024/01/cat.webp)" = 0
    check "probe: CSS is a plain asset" test "$(hdr /styles.css)" = 0
    stop_dev
  else no "wrangler dev with the probe"; fi
else no "wrangler dev started"; fi

echo "[ preview.sh ]"
(cd "$T/example.com" && NO_OPEN=1 PORT=8800 exec "$SK/scripts/preview.sh" >"$T/preview.log" 2>&1) &
PPID2=$!
for _ in $(seq 1 120); do grep -q "running on this computer only" "$T/preview.log" 2>/dev/null && break; sleep 1; done
check "preview.sh serves the site" curl -sf -o /dev/null http://localhost:8800/
check "preview.sh explains itself in plain words" grep -q "running on this computer only" "$T/preview.log"
check "the served page loads the banner" sh -c 'curl -s http://localhost:8800/ | grep -q preview-banner.js'
kill "$PPID2" 2>/dev/null; pkill -f "wrangler dev --port 8800" 2>/dev/null

if [ -n "${ONLINE:-}" ]; then
  echo "[ online ]"
  check "routes-from-sitemap.py reads a real sitemap" sh -c "python3 '$SK/scripts/routes-from-sitemap.py' diego.horse --limit 5 | grep -q '^/  200'"
fi

echo "---- $pass passed, $fail failed ----"
[ "$fail" = 0 ]
