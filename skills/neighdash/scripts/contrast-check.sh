#!/usr/bin/env bash
# WCAG contrast checker. When a pair fails, it also finds the nearest passing shade.
#
# Why this exists: one migrated site inherited a palette from WordPress where
# white on the brand orange was 2.60:1 (needs 3:1) and the link colour was 4.10:1
# (needs 4.5:1). Neither surfaced until Lighthouse ran against the finished
# site, and fixing it meant changing the brand colour after everything was
# built. Check the palette BEFORE building pages on it (traps.md 17).
#
# Also note: Lighthouse only audits the URL you hand it. That site's failing
# link colour lived on 404.html and the homepage scan never saw it, so check
# the palette itself, not just one rendered page.
#
# Usage:
#   contrast-check.sh '#ffffff on #e68b14 large' '#b96a08 on #ffffff'
#   contrast-check.sh --css public/styles.css
set -euo pipefail

if [ "${1:-}" = "--css" ]; then
  CSS="${2:?usage: contrast-check.sh --css <file>}"
  echo "custom properties found in $CSS:"
  grep -oE '\-\-[a-z-]+ *: *#[0-9a-fA-F]{3,8}' "$CSS" | sed 's/^/  /' || echo "  (none)"
  echo
  echo "Pass the pairs that actually render together, e.g.:"
  echo "  scripts/contrast-check.sh '#ffffff on #d67c0b large' '#a85f06 on #ffffff'"
  exit 0
fi

[ $# -ge 1 ] || { echo "usage: contrast-check.sh '<fg> on <bg> [large]' ..." >&2; exit 1; }

python3 - "$@" <<'PY'
import sys, re

def lin(c):
    c /= 255
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

def parse(h):
    h = h.lstrip("#")
    if len(h) == 3: h = "".join(ch * 2 for ch in h)
    return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))

def lum(rgb):
    r, g, b = rgb
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)

def ratio(a, b):
    x, y = lum(a), lum(b)
    hi, lo = max(x, y), min(x, y)
    return (hi + 0.05) / (lo + 0.05)

def hexs(rgb):
    return "#%02x%02x%02x" % rgb

def nudge(rgb, factor):
    return tuple(max(0, min(255, round(c * factor))) for c in rgb)

G, R, Y, N = "\033[32m", "\033[31m", "\033[33m", "\033[0m"
worst = 0

for arg in sys.argv[1:]:
    m = re.match(r"\s*(#[0-9a-fA-F]{3,6})\s+on\s+(#[0-9a-fA-F]{3,6})\s*(large)?\s*$", arg)
    if not m:
        print(f"{R}unparsed:{N} {arg}   (expected '#fff on #000 [large]')")
        worst = 1
        continue
    fg, bg, large = parse(m.group(1)), parse(m.group(2)), bool(m.group(3))
    need = 3.0 if large else 4.5
    r = ratio(fg, bg)
    ok = r >= need
    label = "large" if large else "normal"
    tag = f"{G}PASS{N}" if ok else f"{R}FAIL{N}"
    print(f"  {tag}  {hexs(fg)} on {hexs(bg)}  {r:.2f}:1  (needs {need} for {label} text)")

    if not ok:
        worst = 1
        # Try darkening the background, then the foreground, report whichever
        # reaches the target with the smallest perceptual change.
        for name, which in (("background", "bg"), ("foreground", "fg")):
            for step in range(1, 60):
                f = 1 - step * 0.01
                cand = nudge(bg if which == "bg" else fg, f)
                rr = ratio(fg, cand) if which == "bg" else ratio(cand, bg)
                if rr >= need:
                    print(f"        darken {name} → {hexs(cand)}  ({rr:.2f}:1)")
                    break
sys.exit(worst)
PY
