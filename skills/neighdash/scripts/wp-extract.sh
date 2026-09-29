#!/usr/bin/env bash
# Pull a WordPress site's identity, pages, content, image URLs and post IDs over SSH
# with wp-cli. It runs against the database on the server, so it works even when the
# site's web front end is slow or down.
#
#   SSH_TARGET=user@host.example [SSH_PORT=22] [SSH_KEY=~/.ssh/id_ed25519] \
#   [WP_PATH='$HOME/public_html'] wp-extract.sh > extract.txt
#
# WP_PATH is the WordPress folder ON THE SERVER (cPanel often uses ~/public_html
# for the main domain and ~/<domain> for add-on domains). Needs wp-cli there.
# The IDS section is the ?p= shortlink map: turn it into /_wp-ids.json for the
# legacy-redirect Worker (templates/worker/legacy-redirects.js).
set -euo pipefail
: "${SSH_TARGET:?set SSH_TARGET=user@host}"
PORT="${SSH_PORT:-22}"
WP="${WP_PATH:-\$HOME/public_html}"
SSH=(ssh -p "$PORT" -o BatchMode=yes -o ConnectTimeout=25 -o ServerAliveInterval=8)
[ -n "${SSH_KEY:-}" ] && SSH+=(-i "$SSH_KEY")

"${SSH[@]}" "$SSH_TARGET" "bash -s" <<REMOTE
P="--path=$WP --skip-plugins --skip-themes"
clean(){ sed -E 's/<!-- \/?wp:[^>]*-->//g; s/ style=\"[^\"]*\"//g'; }
echo "### IDENTITY"
echo "name:      \$(wp option get blogname \$P 2>/dev/null)"
echo "tagline:   \$(wp option get blogdescription \$P 2>/dev/null)"
echo "permalink: \$(wp option get permalink_structure \$P 2>/dev/null)"
echo "front:     show_on_front=\$(wp option get show_on_front \$P 2>/dev/null) page_on_front=\$(wp option get page_on_front \$P 2>/dev/null)"
echo "### PAGES (id,type,slug,title)"
wp post list --post_type=page,post --post_status=publish --fields=ID,post_type,post_name,post_title --format=csv \$P 2>/dev/null
echo "### IDS (id,url)"
wp post list --post_type=page,post --post_status=publish --fields=ID,url --format=csv \$P 2>/dev/null
echo "### CONTENT (post_content, for reference: convert from the RENDERED pages)"
for id in \$(wp post list --post_type=page,post --post_status=publish --field=ID \$P 2>/dev/null); do
  echo "########## id=\$id \$(wp post get \$id --field=post_name \$P 2>/dev/null) ##########"
  wp post get \$id --field=post_content \$P 2>/dev/null | clean
done
echo "### IMAGES"
for id in \$(wp post list --post_type=page,post --post_status=publish --field=ID \$P 2>/dev/null); do
  wp post get \$id --field=post_content \$P 2>/dev/null
done | grep -oiE 'https?://[^" ]+\.(jpg|jpeg|png|gif|webp|svg)' | sort -u
REMOTE
