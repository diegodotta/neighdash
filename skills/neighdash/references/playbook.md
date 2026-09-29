# The NeighDash playbook

The full procedure, in order. Each step says what to do, what proves it is done,
and which trap it avoids (numbers point into [traps.md](traps.md)). Scripts live
in `${CLAUDE_SKILL_DIR}/scripts/`, templates in `${CLAUDE_SKILL_DIR}/templates/`.

## 0. Before anything

- **Start a handoff doc** in the user's workspace (`CONTEXT.md`): the goal, how to
  reach every server and API, decisions locked with the user, per-site status, and
  a numbered list of learnings. Update it as you go, so a fresh session can pick up
  where this one stopped. Keep secrets out of it (point at where they live instead).
- **Agree the ground rules with the user and write them down:**
  - Work on `dev`. A push to the production branch deploys. Never merge without asking.
  - Anything hard to undo (DNS, zone settings, deleting records or rules, cancelling
    hosting) needs an explicit yes, every time.
  - Nothing is "done" until it is measured on the real router, not just unit tested.

## 1. Inventory and baseline (while the old site is still up)

1. **Lighthouse "before"**, three runs, keep the median:
   `scripts/migration-report.sh <domain> --before https://<domain>/`.
   After the cutover the old site is only reachable by pinning its origin IP
   (`--before-origin <ip>`), and once the hosting is cancelled it is gone for good.
2. **Every URL the old site answers.** Posts, pages, tags, categories, date archives
   and their `/page/N/`, feeds (`/feed/`, `/comments/feed/`, `/<post>/feed/`),
   `?p=` and `?page_id=` shortlinks, `?s=` search, the Yoast/core sitemaps, and every
   `/wp-content/uploads/...` file including the `-1024x683` size variants and
   `-scaled` originals. With SSH: `scripts/wp-extract.sh`. Without: WordPress's
   Tools, Export (every post with its ID and attachment URLs), the sitemaps, and a
   crawl of the rendered site.
3. **Mine the access logs** for what the outside world links: hotlinked images
   (Google Images, forums), URLs baked into mobile apps, share pages. A crawl never
   finds these (trap 12). Without SSH, the owner downloads them from the host panel
   (cPanel calls them "Raw Access").
4. **Snapshot the DNS zone** (every record, exact content, proxied flag, TTL) into
   the handoff folder before touching anything. Where it lives decides how:
   - Already on Cloudflare: export it through the API.
   - At the web host: the owner exports it (cPanel Zone Editor) or screenshots every
     page of it. A zone can't be listed from outside.
   - As a cross-check, `dig` the usual names: the apex, `www`, `mail`, `webmail`,
     `autodiscover`, `ftp`, MX, TXT, `_dmarc`, and DKIM selectors
     (`default._domainkey`, `google`, `selector1`, `selector2`, `k1`, `s1`, `s2`,
     `mandrill`). Unknown selectors can't be guessed, which is why the owner's export
     matters.
   - Check DNSSEC now: `dig DS <domain> +short`. Any answer means it's on (step 6).
5. **Plugins.** List the active plugins (`wp-extract.sh` prints them) and decide each
   one with the user using the plugin map in [limits.md](limits.md): rebuilt
   statically, replaced by a service, a Worker, or dropped. Membership, shop or
   booking plugins mean the site is an app. Stop and talk before going further.
6. **Mail.** Where do mailboxes live: the web host, Google Workspace, Microsoft 365,
   or nowhere? List MX, SPF, DKIM, DMARC and third party *sending* records (newsletter
   tools add DKIM CNAMEs). Note every record that points at the apex itself (on
   cPanel hosts the MX, `mail` and `webmail` often do, trap 31). Mail decides when
   the old host can be cancelled, and a domain that sends newsletters is not a
   "no mail" domain.
7. **WordPress.com is different.** No SSH, no server logs, and it often runs the
   domain's DNS and email (Professional Email). Export content from its dashboard,
   crawl the rendered pages, and plan the nameserver and mail moves with its own
   domain settings. Also check whether the domain is registered through the hosting
   account: then cancelling the hosting can take the domain with it.

## 2. Pick the shape per site

First check the fit with the user: [limits.md](limits.md) lists what's solvable and
what isn't. The honest trade is ownership (every dynamic feature becomes code they
own) and who can edit (owners who don't use git need a git-based editor, or someone
to do it for them).

| Site | Shape |
|---|---|
| Already static | Lift and shift. |
| Small (a handful of pages) | Rebuild fresh as plain HTML and CSS: `scripts/new-site.sh <domain>`. |
| Blog or big site | Markdown files plus a small build script (or an SSG the user likes), Pagefind for search. Keep every URL. |
| Block theme or page builder with live bits | Crawl the rendered pages and clean them. A Worker splices live data in with HTMLRewriter. |

Plain HTML and CSS with no build step is the default for small sites. A build step
earns its place when there are many pages sharing a layout.

## 3. Convert with fidelity

- **Convert from the RENDERED pages, not `post_content`.** WordPress adds layout
  classes, block supports and lazy-load markup at render time (trap 13).
- **Archive an original page before judging a conversion:**
  `scripts/archive-wp.py` saves a page with every asset, served offline. Compare
  measured numbers (`getComputedStyle`, `getBoundingClientRect`) at 1440, 768 and
  480, not screenshots by eye. The per-page fidelity checks are in trap 14.
- **Undo lazy loaders** (Smush and friends park images in `data-src` and
  `data-bg-image`). Decide, and say, whether you reproduce what the editor meant or
  what was actually live. They can differ (trap 15).
- **Media:** WebP at the sizes actually displayed, `srcset` with measured `sizes`
  (never `sizes="auto"`, trap 16). Animated GIFs become H.264 MP4 more often than
  WebP (measure). No file over 25 MiB. Originals stay out of git. When anything
  external links an original URL, keep that URL working with a 301 to the WebP.
- **Fonts:** system fonts are fine unless the user says otherwise. Agree early
  whether the target is "looks the same" or "pixel perfect". It changes the effort.
- **Check the palette's contrast before building pages on it:**
  `scripts/contrast-check.sh '#fff on #e68b14 large'` (trap 17).

## 4. Repo and build

- One **private** repo per site. The site is served from a build folder (`dist/` or
  `public/`), never the repo root, so `.git`, notes, scripts and exports cannot be
  published by construction (trap 1). `templates/assetsignore.template` is the
  second line of defence.
- **Deploy gate in the build command:** `python3 scripts/check-dist.py dist` (edit
  its settings block per site). If it fails, Cloudflare publishes nothing and the
  previous version stays live.
- `_headers` from `templates/_headers`: fingerprinted CSS and JS immutable, media
  30 days, HTML revalidates (trap 18).
- `favicon.ico` at the root, a real `404.html`, `robots.txt`, `sitemap.xml`,
  OpenGraph tags with an image that resolves, analytics if the user had it.
- Pre-deploy: `scripts/safety-check.sh <dir>` must pass.

## 5. The Worker (only if needed)

Most sites need no Worker at all. Add one only for what static files cannot do:
host-based redirects, query-string redirects (`?p=`), redirects that depend on
whether a file exists (old image URLs to WebP), live data splices, a small API.

- Start from `templates/worker/legacy-redirects.js` and
  `templates/wrangler.worker.jsonc`.
- **`run_worker_first` is a path list, never `true`** (trap 2). With
  `not_found_handling: "404-page"`, a URL with no file behind it never reaches the
  Worker unless it is listed (trap 3).
- **www to apex is a zone Redirect Rule**, not Worker code:
  `templates/www-redirect-rule.json` (recipe in [cloudflare.md](cloudflare.md)).
- `_redirects` covers simple path redirects and keeps the query string on a plain
  destination (trap 19). It cannot match on host or query.

## 6. Cloudflare project

Recipes in [cloudflare.md](cloudflare.md).

**Zone access first.** The wrangler login can deploy Workers but can't touch DNS or
rules. Add the Cloudflare MCP server now (it restarts the session: update CONTEXT.md
and tell the owner first), or use a scoped token the owner saves to a file (SKILL.md,
Tools). Never a token pasted into the chat.

**If the domain isn't on Cloudflare yet**, move its DNS first. This doesn't change
the website, but done carelessly it breaks email.

0. **DNSSEC.** If `dig DS <domain> +short` answers, DNSSEC is on at the registrar.
   The owner turns it off there, then wait for the DS record's TTL to pass before
   changing nameservers. Otherwise validating resolvers reject the domain, site and
   email both (trap 32). Turn it back on from Cloudflare once the zone is Active.
1. Add the site to Cloudflare (free plan). Cloudflare imports the existing records by
   scanning, and it can miss some. Compare the imported zone with the snapshot from
   step 1, especially MX, TXT (SPF, DKIM, DMARC) and any subdomains, and add what's
   missing.
2. Set the imported web records to **DNS only** (grey cloud) for now, so visitors
   still reach the old host exactly as before. Proxying the old WordPress through
   Cloudflare can cause redirect loops or certificate errors, and nothing here needs it.
3. The owner changes the nameservers at their registrar. Guide them click by click,
   it's their account.
4. Wait for the zone to show as Active (minutes to a day). Send a test email to the
   domain and check it arrives before going further.
5. The registration itself can stay where it is. Moving it to Cloudflare Registrar
   is optional and can wait.

- Create the Worker **git-connected with a production-branch-only trigger.** A
  Worker created in the dashboard also gets a "deploy non-production branches"
  trigger, which deploys `dev` too (trap 5). Delete it, or create through the API.
- A build reported as `stopped` means finished, not failed. The workers.dev URL is
  the ground truth (trap 20).

## 7. Prove it before switching the site

- **Route check on the real router:** write `routes.txt` from the inventory in step
  1 and run `scripts/route-check.sh routes.txt http://127.0.0.1:8787` against
  `npx wrangler dev`, then against the workers.dev URL. Every old URL must answer
  as planned (200, or 301 to the right place) and nothing private may be served.
- **Which paths run the Worker:** swap in `templates/worker/probe.js` locally
  (never committed) and check the `x-neighdash-worker` header. Status codes alone
  can't show this.
- `scripts/qa-check.sh <url>`: pages, leaks, 404, OpenGraph, analytics.
- For any change that should not alter how pages look: `scripts/pixel-diff.sh`,
  with a control run first (trap 11).

**Freeze WordPress edits** from the day of the final crawl. Tell the owner the date.
Anything edited in WordPress after it is lost unless you crawl again.

## 8. Cutover (user says yes first)

The zero-downtime version, in one scripted API call (recipe in
[cloudflare.md](cloudflare.md)):

0. **Mail dependencies first** (trap 31). List every record whose content is the apex
   or `www` (MX targets, `mail`, `webmail`, `autodiscover`, `ftp` CNAMEs) and every
   SPF that uses `a` or `mx`. If there are any: create `mail.<domain>` as an `A` record
   to the old host's IP (DNS only), repoint the MX and those CNAMEs to it, rewrite SPF
   with an explicit `ip4:` for the old host, then send a test email in and out. Only
   when mail passes, continue. The cutover script in cloudflare.md refuses otherwise.
1. Back up the apex `A`/`AAAA` and `www` `CNAME` records.
2. Delete **only** those. Never MX, SPF, DKIM, DMARC, or mail hosts.
3. Attach both custom domains to the Worker through the API. If either attach
   fails, put the records back automatically.
4. Then declare the domains in `wrangler.jsonc` and push the production branch.
5. Create the www Redirect Rule (before, or with, the first Worker that relies on it).
6. Check Bot Fight Mode: both `fight_mode` and `enable_js` off (trap 8).
7. Purge the cache, then probe several times, logging status and bytes (trap 9).
8. If your own machine says the site is down, check with `curl --resolve` before
   believing it (trap 10).

## 9. After

- `scripts/migration-report.sh <domain> --after` then `--report`. Same Lighthouse
  setup on both sides. When lab and observed timings disagree, trust the observed
  ones (trap 21).
- Fix what Lighthouse flags, verifying visual changes with screenshots.
- Read the carbon section honestly (see "Reading the report" below).
- Watch the account's daily Worker requests for a few days (GraphQL query in
  [cloudflare.md](cloudflare.md)).
- **Lock down the old WordPress.** Until the hosting is cancelled it stays online at
  the host (by IP or a temporary address), unpatched. Put it behind a password or in
  maintenance mode right after the cutover.
- **Mail before cancelling.** Three cases:
  - Mail at Google Workspace or Microsoft 365: nothing to move. Keep their records.
  - No mailboxes at all: an explicit null mail policy (null MX, `v=spf1 -all`, DMARC
    `p=reject`), unless something *sends* as the domain.
  - **Mailboxes at the web host** (the usual small business case): pick a provider
    with the owner (it costs a few dollars per mailbox per month), create the
    mailboxes, copy the old mail over IMAP, update the owner's phone and computer,
    then change the MX after a yes. Keep the old host until mail has stopped
    arriving there. Cloudflare Email Routing only forwards incoming mail, it can't be
    the mailbox the owner replies from.
- Cancel the old hosting only when nothing (web, mail, cron, backups, the domain
  registration) depends on it. Delete the WordPress install and its database there,
  and keep an offline backup of both.

## Reading the report

`migration-report.sh` estimates energy with the Sustainable Web Design Model (the
one behind websitecarbon.com), which works from bytes transferred only. The report
itself explains the caveats. Say them to the user too:

- The per-visit device saving is overstated by the byte model. The report measures
  main-thread time to give an honest range.
- A shared server's idle power isn't in the byte model, and leaving a shared host
  is an attributional saving, not a physical one.
- The migration itself cost energy (the agent's inference is the biggest and least
  measurable term). A carbon payback in months to years is normal at low traffic.
- For most people this is not a carbon decision. Don't present it as one.
