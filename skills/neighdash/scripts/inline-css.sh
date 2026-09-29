#!/usr/bin/env bash
# Re-inline a site's styles.css into every HTML page, between the markers:
#   <style>/* styles.css:begin ... */  ...css...  /* styles.css:end */</style>
#
# Why: inlining a small stylesheet removes the render-blocking CSS request
# (a Lighthouse audit). styles.css stays the single source of truth, edit it,
# then run this to push the change into the pages.
#
# Usage: inline-css.sh <site-folder>   (the folder with styles.css and the pages)
set -euo pipefail
DIR="${1:?usage: inline-css.sh <site-dir>}"
CSS="$DIR/styles.css"
[ -f "$CSS" ] || { echo "no styles.css in $DIR" >&2; exit 1; }

python3 - "$DIR" "$CSS" <<'PY'
import pathlib, re, sys

site, css_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
css = css_path.read_text().rstrip()
BEGIN = "/* styles.css:begin (regenerate with NeighDash inline-css.sh) */"
block = f"<style>{BEGIN}\n{css}\n/* styles.css:end */</style>"
pat = re.compile(r"<style>/\* styles\.css:begin.*?styles\.css:end \*/</style>", re.S)

changed = skipped = 0
for p in sorted(site.rglob("*.html")):
    if ".git" in p.parts:
        continue
    h = p.read_text()
    if not pat.search(h):
        print(f"  -- no marker, skipped: {p.relative_to(site)}")
        skipped += 1
        continue
    new = pat.sub(lambda _: block, h, count=1)
    if new != h:
        p.write_text(new)
        print(f"  updated: {p.relative_to(site)}")
        changed += 1
    else:
        print(f"  current: {p.relative_to(site)}")

print(f"---- {changed} updated, {skipped} without markers ----")
PY
