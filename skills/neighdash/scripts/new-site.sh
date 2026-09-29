#!/usr/bin/env bash
# Scaffold a small static site for Cloudflare Workers static assets.
#
#   new-site.sh example.com [parent-dir]
#
# Creates <parent-dir>/example.com/ with the site files in public/ (the only folder
# Cloudflare serves), a wrangler.jsonc, .gitignore and public/.assetsignore.
# No build step: edit public/ directly. For a blog, use a build script that writes
# dist/ instead, and templates/wrangler.worker.jsonc if it needs legacy redirects.
set -euo pipefail
DOMAIN="${1:?usage: new-site.sh <domain> [parent-dir]}"
PARENT="${2:-.}"
T="$(cd "$(dirname "$0")/../templates" && pwd)"
DEST="$PARENT/$DOMAIN"
NAME="${DOMAIN//./-}"            # example.com -> example-com (the Worker name)
[ -e "$DEST" ] && { echo "refusing: $DEST already exists"; exit 1; }

mkdir -p "$DEST/public/assets"
sed -e "s/SITE-NAME-HERE/$NAME/" -e 's#"\./dist"#"./public"#' "$T/wrangler.static.jsonc" > "$DEST/wrangler.jsonc"
cp "$T/gitignore.template" "$DEST/.gitignore"
sed -i.bak '/^dist\/$/d' "$DEST/.gitignore" && rm "$DEST/.gitignore.bak"   # public/ is source here
cp "$T/assetsignore.template" "$DEST/public/.assetsignore"
cp "$T/_headers" "$DEST/public/_headers"
cp "$T/preview-banner.js" "$DEST/public/preview-banner.js"   # the "this is a preview" bar

cat > "$DEST/public/index.html" <<HTML
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$DOMAIN</title>
<meta name="description" content="">
<link rel="canonical" href="https://$DOMAIN/">
<meta property="og:title" content="$DOMAIN"><meta property="og:type" content="website">
<meta property="og:url" content="https://$DOMAIN/"><meta property="og:image" content="https://$DOMAIN/assets/og.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/favicon.ico">
<script src="/preview-banner.js" defer data-live="$DOMAIN"></script>
<!-- TODO: analytics snippet, if the old site had one -->
<link rel="stylesheet" href="/styles.css"></head>
<body><main class="wrap"><h1>$DOMAIN</h1><p>Coming soon.</p></main></body></html>
HTML

cat > "$DEST/public/styles.css" <<'CSS'
:root{--maxw:1024px}*{box-sizing:border-box}
body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;line-height:1.6}
img{max-width:100%;height:auto;display:block}
.wrap{max-width:var(--maxw);margin:0 auto;padding:24px}
CSS

cat > "$DEST/public/404.html" <<HTML
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="robots" content="noindex">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Not found</title><link rel="stylesheet" href="/styles.css">
<script src="/preview-banner.js" defer data-live="$DOMAIN"></script></head>
<body><main class="wrap"><h1>Page not found</h1><p><a href="/">Home</a></p></main></body></html>
HTML

printf 'User-agent: *\nAllow: /\n\nSitemap: https://%s/sitemap.xml\n' "$DOMAIN" > "$DEST/public/robots.txt"
cat > "$DEST/public/sitemap.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://$DOMAIN/</loc></url></urlset>
XML
printf '# %s\n\nStatic site on Cloudflare Workers static assets (NeighDash). Only public/ is served.\n\nPreview on this computer: run NeighDash'"'"'s scripts/preview.sh in this folder. Every page loads\n/preview-banner.js, which shows a yellow bar anywhere but %s itself.\nNot `python3 -m http.server`: it ignores _redirects and _headers.\n' "$DOMAIN" "$DOMAIN" > "$DEST/README.md"

echo "Scaffolded $DEST  (Worker name: $NAME)"
echo "Still needed: public/favicon.ico and public/assets/og.png"
