#!/usr/bin/env python3
"""
Deploy gate: fail the Cloudflare build (and so the deploy) when the build folder
is wrong. Put it at the end of the build command:

    python3 build.py && python3 scripts/check-dist.py dist

A failing check means nothing is published and the previous version stays live.
Each check catches a failure that is silent otherwise. Edit SETTINGS per site.
"""
import pathlib, re, sys, urllib.parse

SETTINGS = {
    "min_pages": 1,              # fewer index.html pages than this = content failed to load
    "required": ["index.html", "404.html", "robots.txt", "sitemap.xml", "favicon.ico"],
    "analytics": None,           # e.g. "G-XXXXXXX": every page but 404 must carry it
    "draft_marker": None,        # a string only draft pages contain, e.g. "draft-banner"
    "domain": None,              # e.g. "example.com": absolute links to its uploads must exist here
    "max_files": 20000,          # Workers static assets, free plan
    "max_bytes": 25 * 1024 * 1024,
}

DIST = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "dist").resolve()
S = SETTINGS
errors = []
fail = errors.append

if not DIST.is_dir():
    sys.exit(f"no build folder at {DIST}")

files = [f for f in DIST.rglob("*") if f.is_file()]
pages = [p for p in files if p.suffix == ".html"]

if len([p for p in pages if p.name == "index.html"]) < S["min_pages"]:
    fail(f"only {len(pages)} pages built (expected at least {S['min_pages']})")
if len(files) >= S["max_files"]:
    fail(f"{len(files)} files, at or over the {S['max_files']} asset limit")
for f in files:
    rel = f.relative_to(DIST)
    if f.stat().st_size > S["max_bytes"]:
        fail(f"over 25 MiB (Workers refuses it): {rel}")
    if f.suffix in (".md", ".py", ".pyc", ".sh", ".sql", ".bak", ".log") or f.name.startswith((".env", ".dev.vars")) \
            or ".git" in rel.parts or "__pycache__" in rel.parts:
        fail(f"source or private file in the build folder: {rel}")
for core in S["required"]:
    if not (DIST / core).exists():
        fail(f"missing {core}")

# The local admin bar (templates/neighdash-admin.js) and its page map only belong in
# preview builds. Not a setting: a deployable build never carries them.
for marker in ("neighdash-pages.json", "neighdash-build.txt"):
    if any(f.name == marker for f in files):
        fail(f"{marker} is in the build folder: this is a preview build, never deploy it")

ref_re = re.compile(r'(?:src|poster|href)="(/[^"#?]+)"|srcset="([^"]+)"')
own = re.compile(rf'https://(?:www\.)?{re.escape(S["domain"])}(/wp-content/[^"\s<>)]+)') if S["domain"] else None
seen = set()
for p in pages:
    html = p.read_text(encoding="utf-8", errors="ignore")
    rel = p.relative_to(DIST)
    if "neighdash-admin.js" in html:
        fail(f"loads the local admin bar (preview build): {rel}")
    if S["draft_marker"] and S["draft_marker"] in html:
        fail(f"draft published: {rel}")
    if S["analytics"] and S["analytics"] not in html and rel.name != "404.html":
        fail(f"no analytics tag: {rel}")
    if own:  # absolute links are fine (og:image must be absolute) if the file exists here
        for u in set(own.findall(html)):
            if not (DIST / urllib.parse.unquote(u).lstrip("/")).exists():
                fail(f"absolute link to a file this site doesn't have: {u} (in {rel})")
    for m in ref_re.finditer(html):
        urls = [m.group(1)] if m.group(1) else [u.split()[0] for u in m.group(2).split(",") if u.strip()]
        for u in urls:
            if not u.startswith("/") or u.startswith("//") or u in seen:
                continue
            t = DIST / urllib.parse.unquote(u).lstrip("/")
            if not (t.exists() or (t / "index.html").exists() or t.with_suffix(".html").exists()):
                seen.add(u)
                if re.search(r"\.[a-z0-9]{2,5}$", u, re.I):   # only flag files, not page links
                    fail(f"missing file {u} (in {rel})")

if errors:
    print(f"deploy gate FAILED ({len(errors)}):")
    for e in errors[:60]:
        print("  ✗", e)
    sys.exit(1)
print(f"deploy gate passed: {len(pages)} html pages, {len(files)} files, "
      f"{sum(f.stat().st_size for f in files) / 1e6:.0f} MB")
