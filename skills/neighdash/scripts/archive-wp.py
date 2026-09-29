#!/usr/bin/env python3
"""Archive one page of the old WordPress site as a self-contained folder.

    python3 archive-wp.py example.com /about/ old-about
    python3 archive-wp.py example.com /about/ old-about --origin 203.0.113.10
    python3 -m http.server 8124 --directory old-about   # the real thing, offline

Every asset the page references is downloaded and rewritten to a relative path,
so the result renders offline. That is the only honest way to compare a converted
page with the original (playbook step 3): measure both, don't eyeball them.

--origin pins the hostname to the old server's IP, for when DNS already points at
the new site. TLS verification is skipped in that case (old origins often carry a
Cloudflare Origin certificate).

Learned the hard way: WordPress writes href='...' with SINGLE quotes, so a grep
for href="..." finds no stylesheets and you end up measuring an unstyled page.
This matches the URLs themselves, not the attributes (traps.md 14).
"""
import argparse
import pathlib
import re
import subprocess
import sys
import urllib.parse


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("host", help="the site's hostname, e.g. example.com")
    ap.add_argument("path", help="page path, e.g. /about/")
    ap.add_argument("outdir", help="folder to write the archived page into")
    ap.add_argument("--origin", help="old server IP to pin the hostname to")
    a = ap.parse_args()

    asset_re = re.compile(rf'https?://(?:www\.)?{re.escape(a.host)}/(?:wp-content|wp-includes)/[^\s"\'\)]+')

    def fetch(url: str, dest: pathlib.Path) -> bool:
        cmd = ["curl", "-sL", "-m", "60", "-o", str(dest), "-w", "%{http_code}", url]
        if a.origin:
            cmd[1:1] = ["-k", "--resolve", f"{a.host}:443:{a.origin}", "--resolve", f"www.{a.host}:443:{a.origin}"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.stdout.strip() != "200" or not dest.exists() or dest.stat().st_size == 0:
            dest.unlink(missing_ok=True)
            return False
        return True

    out = pathlib.Path(a.outdir)
    (out / "a").mkdir(parents=True, exist_ok=True)
    page = out / "index.html"
    if not fetch(f"https://{a.host}{a.path}", page):
        print(f"  FAILED to fetch {a.path}", file=sys.stderr)
        return 1
    html = page.read_text(errors="ignore")

    urls = sorted({u.rstrip(",") for u in asset_re.findall(html)})
    ok = 0
    for u in urls:
        fname = re.sub(r"[^A-Za-z0-9._-]", "_", urllib.parse.urlsplit(u).path.lstrip("/"))
        dest = out / "a" / fname
        if dest.exists() or fetch(u, dest):
            ok += 1
            html = html.replace(u, f"a/{fname}")
    page.write_text(html)

    left = len(asset_re.findall(html))
    size = sum(f.stat().st_size for f in (out / "a").iterdir()) / 1e6
    print(f"  {a.path:24} {ok}/{len(urls)} assets  {size:5.1f}MB  unresolved refs: {left}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
