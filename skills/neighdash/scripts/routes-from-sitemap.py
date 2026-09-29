#!/usr/bin/env python3
"""Write a starting routes.txt for route-check.sh from the OLD site's sitemap.

    python3 routes-from-sitemap.py example.com > routes.txt
    python3 routes-from-sitemap.py https://example.com/sitemap_index.xml > routes.txt
    python3 routes-from-sitemap.py example.com --origin 203.0.113.10 > routes.txt

Run it BEFORE the cutover, while the sitemap still comes from the old site (or pin
the old server with --origin). Every page the old site listed becomes a line that
must answer 200 on the new one. Then it adds the checks every NeighDash site needs
(nothing private served, a real 404, www to apex on the live site) and commented
examples of the legacy URL shapes to fill in from the inventory (playbook step 1).

Given a bare domain it tries WordPress's usual sitemaps (Yoast's sitemap_index.xml,
core's wp-sitemap.xml, sitemap.xml) and follows sitemap indexes.
"""
import argparse, re, subprocess, sys, urllib.parse

ap = argparse.ArgumentParser()
ap.add_argument("site", help="a domain (example.com) or a sitemap URL")
ap.add_argument("--origin", help="old server IP, to read the sitemap from it after DNS moved")
ap.add_argument("--limit", type=int, default=0, help="keep only the first N pages (0 = all)")
a = ap.parse_args()

def get(url):
    # curl, not urllib: python.org's Python on macOS ships without the system's
    # certificates, so urllib fails on every HTTPS site until "Install Certificates".
    u = urllib.parse.urlsplit(url)
    cmd = ["curl", "-sL", "--max-time", "30", "-A", "neighdash-routes/0.1", url]
    if a.origin:  # the old origin's certificate often doesn't match the name
        cmd[1:1] = ["-k", "--resolve", f"{u.hostname}:443:{a.origin}", "--resolve", f"{u.hostname}:80:{a.origin}"]
    r = subprocess.run(cmd, capture_output=True, text=True, errors="ignore")
    if r.returncode != 0:
        print(f"# could not read {url} (curl exit {r.returncode})", file=sys.stderr)
    return r.stdout

if a.site.startswith("http"):
    starts = [a.site]
    domain = urllib.parse.urlsplit(a.site).netloc
else:
    domain = a.site.strip("/")
    starts = [f"https://{domain}/{p}" for p in ("sitemap_index.xml", "wp-sitemap.xml", "sitemap.xml")]
apex = re.sub(r"^www\.", "", domain)

pages, seen = [], set()
def walk(url, depth=0):
    if url in seen or depth > 3:
        return
    seen.add(url)
    xml = get(url)
    locs = re.findall(r"<loc>\s*([^<\s]+)\s*</loc>", xml)
    if "<sitemapindex" in xml:
        for l in locs:
            walk(l.replace("&amp;", "&"), depth + 1)
    else:
        pages.extend(l.replace("&amp;", "&") for l in locs)

for s in starts:
    walk(s)
    if pages:
        break

paths = []
for p in pages:
    u = urllib.parse.urlsplit(p)
    if re.sub(r"^www\.", "", u.netloc) != apex:
        continue
    path = u.path or "/"
    if u.query:
        path += "?" + u.query
    if path not in paths:
        paths.append(path)
if a.limit:
    paths = paths[: a.limit]
if not paths:
    sys.exit(f"no pages found in the sitemaps of {domain}")

print(f"# routes.txt for {apex}, {len(paths)} pages from its sitemap. Check with:")
print("#   route-check.sh routes.txt http://localhost:8787    (preview.sh running)")
print(f"#   route-check.sh routes.txt https://{apex}             (after the cutover)")
print("\n# every page the old site listed")
for p in paths:
    print(f"{p}  200")
print("""
# never served (traps.md 1 and 4)
/.git/config            404
/.env                   404
/wrangler.jsonc         404
/README.md              404
/neighdash-no-such-page/ 404

# the old WordPress admin should go somewhere sensible, not 404 (a _redirects line)
# /wp-login.php          301  /
# /wp-admin/             301  /

# legacy URL shapes, one real example of each from the inventory (playbook step 1):
# /?p=123                                   301  /some-post/
# /?s=cats                                  302  /search/?q=cats
# /wp-content/uploads/2024/01/photo.jpg     301  /wp-content/uploads/2024/01/photo.webp
# /wp-content/uploads/2024/01/photo-1024x683.jpg  301  /wp-content/uploads/2024/01/photo.webp
# /feed/                                    200  xml
# /comments/feed/                           301  /feed/
# /tag/some-tag/page/99/                    301  /tag/some-tag/
# /sitemap_index.xml                        301  /sitemap.xml
""")
print(f"# www to apex, checked only against the live site")
print(f"live https://www.{apex}/  301  https://{apex}/")
