#!/usr/bin/env bash
# Pre-deploy safety gate for a site repo. Run before the first push and before any
# deploy: it catches what should never be published (traps.md 1 and 4).
#
#   safety-check.sh [site-dir]     (default: current dir)
#
# Checks: which folder wrangler serves (never the repo root without an
# .assetsignore that excludes .git), no secret-like files, no private-key or token
# patterns, no file over the 25 MiB Workers limit.
set -uo pipefail
DIR="${1:-.}"; cd "$DIR" || { echo "no such dir: $DIR"; exit 2; }
fail=0
red(){ printf "  \033[31mFAIL\033[0m %s\n" "$1"; fail=1; }
grn(){ printf "  \033[32mOK\033[0m   %s\n" "$1"; }
EXCL=(-not -path './.git/*' -not -path './node_modules/*' -not -path './.wrangler/*')

echo "SAFETY: $(pwd)"

# 1) what does wrangler publish?
ASSETS=$(python3 - <<'PY' 2>/dev/null
import json, re, pathlib
p = pathlib.Path("wrangler.jsonc") if pathlib.Path("wrangler.jsonc").exists() else pathlib.Path("wrangler.json")
t = re.sub(r'(?m)^\s*//.*$|(?<=[,{\[\s])//[^\n"]*$', "", p.read_text())
t = re.sub(r",(\s*[}\]])", r"\1", t)
print(json.loads(t).get("assets", {}).get("directory", ""))
PY
)
if [ -z "$ASSETS" ]; then
  red "no wrangler.jsonc with assets.directory found"
else
  norm="${ASSETS#./}"; norm="${norm%/}"
  if [ -z "$norm" ] || [ "$norm" = "." ]; then
    if [ -f .assetsignore ] && grep -qxF '.git' .assetsignore; then
      grn "serves the repo root, .assetsignore excludes .git (prefer a build folder)"
    else
      red "serves the repo root WITHOUT an .assetsignore excluding .git (the first-deploy .git leak)"
    fi
  else
    grn "serves ./$norm only"
    [ -f "$norm/.assetsignore" ] && grn "$norm/.assetsignore present" \
      || printf "  \033[33mWARN\033[0m no %s/.assetsignore (copy templates/assetsignore.template)\n" "$norm"
  fi
fi

# 2) no secret, key or env files anywhere in the tree
found=$(find . -type f "${EXCL[@]}" \( -name '.env' -o -name '.env.*' -o -name '.dev.vars*' -o -name '*.pem' \
        -o -name '*.key' -o -name 'id_rsa*' -o -name 'id_ed25519*' -o -iname '*secret*' -o -iname '*credential*' \) \
        -not -name '*.example' 2>/dev/null)
tracked=""
for f in $found; do git ls-files --error-unmatch "$f" >/dev/null 2>&1 && tracked="$tracked $f"; done
[ -z "$tracked" ] && grn "no secret/key/env files tracked by git" || { red "secret-like files tracked by git:"; printf '       %s\n' $tracked; }

# 3) private-key / token patterns inside files
hits=$(grep -rIlE '(BEGIN (RSA|OPENSSH|EC|DSA|PRIVATE) KEY)|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{40,}|xox[baprs]-[A-Za-z0-9-]+|sk-[A-Za-z0-9_-]{32,}' \
        . --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.wrangler 2>/dev/null)
[ -z "$hits" ] && grn "no private-key / token patterns in files" || { red "possible secret in:"; echo "$hits" | sed 's/^/       /'; }

# 4) files over the 25 MiB Workers static-asset limit
big=$(find . -type f -size +25M "${EXCL[@]}" 2>/dev/null)
[ -z "$big" ] && grn "no files over 25 MiB" || { red "over 25 MiB (re-encode or move to R2):"; echo "$big" | sed 's/^/       /'; }

echo "----"
if [ "$fail" = 0 ]; then echo "SAFE to push"; else echo "NOT SAFE: fix the above first"; exit 1; fi
