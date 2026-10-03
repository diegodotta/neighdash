# Traps

Every one of these happened on a real migration. Each entry: what you see, why,
and what to do. The playbook points here by number.

## Publishing things that should never be public

**1. The repo root gets published, `.git` included.** Workers static assets serve
the whole folder you point them at. The first deploy of a site served `/.git/config`.
Serve a build folder (`dist/` or `public/`) so private files can't be published by
construction, and keep `.assetsignore` as the second line of defence.

**4. Ignore files by class, not by name.** An ignore list had `check.py` but not its
compiled `__pycache__/check.cpython-312.pyc`, which went live (bytecode decompiles
back to the script and embeds the absolute local path). A `MIGRATION-REPORT.md` was
one merge away from the same fate because only `README.md` was listed. Ignore `*.md`,
`__pycache__`, `*.pyc`, `.env*`, `.dev.vars*` as classes. Audit the served files'
comments once for anything sensitive.

## The Worker and the free plan

**2. `run_worker_first: true` spends the account's free Worker budget on every file.**
The Workers Free plan allows 100,000 Worker requests a day **per account**, shared by
every site on it. Past that, Worker-backed routes answer Error 1027 until midnight UTC.
Requests served straight from static assets are free and unlimited. With `true`, one
page view cost about 10 Worker requests (HTML, CSS, JS, every image), 31k on a normal
day across two small sites. A post that gets shared would have taken them all down.
Use a path list with only what the Worker must handle.

**3. With `not_found_handling: "404-page"`, an unmatched URL never reaches the Worker.**
The first narrowed list (`["/", "/api/*"]`) passed every page test and silently 404'd
seven legacy redirects (old image URLs, `/page/N/`, old feeds, old sitemaps), because
those URLs have no file behind them. List every legacy URL shape the Worker rewrites,
with `!` exceptions for the real files that share the prefix. Over-matching is harmless
if the Worker serves the asset first. Only the route check on `wrangler dev` caught it.

**22. When a path matches a file, the Worker doesn't run at all** unless the path is in
`run_worker_first`. A form handler's HTMLRewriter was correct and simply never
executed. No error, no log, just the plain file. Same fix, same proof: the probe.

**23. Validate live data before it replaces the last good snapshot.** An upstream JSON
feed briefly returned a well-formed response with no entries. The build parsed it,
overwrote the good snapshot, and shipped an empty section. Refuse responses the page
would render nothing from.

## Cloudflare setup and cutover

**5. Dashboard-created Workers deploy every branch.** They ship with a second build
trigger, "Deploy non-production branches", so every push to `dev` deploys too. Delete
it, or create the Worker through the API so it never exists.

**6. The deployments API can't tell you whether a Worker is git-connected.** It
reports `source: "wrangler"` for Cloudflare-built deploys too (the build runs
`wrangler deploy`). Ask the Builds API for the Worker's build config instead.

**7. Attaching a custom domain fails while the old DNS records exist** (`100117:
Hostname already has externally managed DNS records`). Delete the apex `A`/`AAAA` and
`www` `CNAME` first, then attach, in one scripted call that restores the records if the
attach fails. Waiting for a git build between the two leaves the domain dark.

**8. Bot Fight Mode is the biggest performance drag, and switching it off leaves half
of it on.** With `enable_js` it injects a challenge script: 1,309 ms of main-thread
work on one site, about six times Google Analytics. The dashboard toggle sets
`fight_mode: false` but leaves `enable_js: true`. Check both. Via the API, `PUT` only
`{"fight_mode": false, "enable_js": false}`.

**9. The edge cache lies, in both directions.** After a deploy, five identical requests
came back old, new, new, old, old. Deleted pages kept answering 200. Purge after every
content deploy, then probe several times and log status and byte size, not just "does
it contain X" (a failed request looks the same as old content).

**10. A cutover looks like an outage from your own machine.** The local resolver keeps
the deleted records for minutes while public DNS is already right. Check with
`curl --resolve <host>:443:<cloudflare-ip>` before believing a failure.

**20. Build status `stopped` means finished.** Not failed. Probe the workers.dev URL.

**24. `wrangler dev` side effects.** Several instances need their own
`--inspector-port`. For a site served from the repo root, point `--persist-to`
outside the repo, or wrangler's own state lands in the watched folder and reloads
forever.

**25. The wrangler OAuth login is not a zone admin.** It can deploy Workers, but DNS,
rules, bot management and the Builds API answer "Authentication error". Use the
Cloudflare MCP server or a scoped API token for zone work.

**26. Quote TXT record content when writing it through the API** (`'"v=spf1 ..."'`).
Unquoted works but shows a warning in the dashboard.

**28. Two repos can share one hostname only as separate Workers.** Every deploy
publishes a complete asset manifest, so two pipelines publishing into one Worker erase
each other. A Worker on a path route (`example.com/games/*`) runs in front of the
Custom Domain Worker. The route lives in account state, not git. Write it down.

**31. Mail that points at the website's address breaks at cutover.** On typical
cPanel hosts the MX record is the domain itself (`MX 0 example.com`), `mail`,
`webmail`, `autodiscover` and `ftp` are CNAMEs to it, and SPF trusts `+a +mx`. The
cutover deletes the apex record and hands the name to the Worker, so incoming mail,
phone and desktop mail settings, and SPF all break, silently. Before the cutover give
mail its own `mail.<domain>` A record to the old host (DNS only), repoint MX and the
CNAMEs to it, write SPF with an explicit `ip4:`, and pass a mail test. It didn't bite
the migrations this skill came from only because their mail already had its own hosts.

**32. DNSSEC turns a nameserver change into an outage.** If DNSSEC is on at the
registrar (`dig DS <domain> +short` answers), switching nameservers to Cloudflare
leaves a DS record that no longer matches, and validating resolvers refuse the domain:
site and email both. Turn DNSSEC off at the registrar, wait for the DS TTL, switch,
then enable it again from Cloudflare.

**29. The agent will deploy "just this once".** In the first migration the agent merged
to the production branch twice without asking, the second time right after being told
why not to. Put the rule in the agent's memory and in each repo's instructions.

## Conversion

**12. A crawl doesn't know which files the outside world links.** A mobile app fetched
an image no page referenced. Mine the access logs for every upload URL before deciding
what to carry over. Skip multi-megabyte originals requested once (bots).

**13. Convert from rendered pages.** WordPress adds layout classes and block supports at
render time, so `post_content` alone loses the layout.

**14. Per-page fidelity checks** (each one cost a round of rework):
- Confirm the stylesheets actually loaded in your archived copy. WordPress writes
  `href='...'` with single quotes, so a grep for `href="` finds nothing.
- Read every block attribute. `minHeight` and `minHeightUnit` are separate: dropping
  the unit turned a `100vh` hero into 100 pixels.
- Count `<img>` in the original and the converted page. Images inside covers and
  columns get missed.
- A block on the home page is not necessarily on every page. Check a second page.
- `wp:columns` is a layout. Flattening it stacks copy above media.
- Themes indent lists by 40px. Less and the bullets hang outside the column.

**15. Lazy loaders hide content.** Smush parks images in `data-src` and background
images in `data-bg-image`, and once double-escaped the quotes so the live site showed a
black band for months. "Faithful to the editor" and "what was live" can disagree. Pick
one and say which.

**16. Image traps.** `sizes="auto"` made the browser pick a 300px image for a much
larger box. Measure each image's displayed width and write real `sizes`. `gif2webp`
produced 1.5 MB from a 1.2 MB GIF while H.264 gave 467 KB. Measure, don't assume.

**17. Check contrast before building on a palette.** White on the brand orange was
2.60:1 (needs 3:1) and nobody noticed until Lighthouse ran on the finished site. And
Lighthouse only audits the URL you give it: the failing link colour lived on the 404
page.

**18. Workers static assets default to `max-age=0, must-revalidate` on everything.**
Add a `_headers` file. Fingerprint CSS and JS (`?v=<hash>`) to cache them for a year.

**19. `_redirects` keeps the query string** on a plain destination and drops it when
the destination has its own query. It can't match on host or on query.

**33. A plain file server lies about redirects.** `python3 -m http.server` (or opening
the HTML files directly) serves the files but ignores `_redirects`, `_headers`,
`not_found_handling` and the Worker. Redirects look broken, or look fine when they
aren't, and the 404 page never shows. Preview and test with `wrangler dev`
(`scripts/preview.sh`), which is Cloudflare's own router running locally.

**34. The preview build and the real build share a folder.** With editing from the
preview, `build.py --preview` writes drafts, the admin bar and `neighdash-pages.json`
into the same `dist/` the real build uses. Commit that folder, or `wrangler deploy` from
the laptop, and the drafts go live. Keep `dist/` out of git (`templates/gitignore.template`
does), deploy only through the build command, and keep `check-dist.py` at the end of it:
it refuses a build carrying the bar or the page map.

**27. Put `favicon.ico` at the root.** Browsers ask for it regardless of `<link>` tags.

## Measuring

**11. A refactor that must not change how pages look is verified by screenshots.**
Purging CSS once cut a selector in half and unstyled every page while all 66 route
checks passed (they read status codes, not pixels). Run a control first (baseline vs
an identical copy) to learn the noise floor.

**21. Compare old and new with one identical Lighthouse setup, and trust observed
timings over simulated ones.** One site "regressed" from 69 to 56 with a 10 s LCP. The
cause was a one second first-paint delay that only happened when Lighthouse launched
Chrome itself, which its slow-phone simulation stretched into ten. The same setup on
both sides showed 54 to 89. Also: native `loading="lazy"` makes Lighthouse count
images a JS lazy loader hid, so "page weight +29%" was a counting difference.

**30. Single Lighthouse runs are noise.** One early pair reported the old site at 77 and
"FCP 63% worse" after migrating, both sampling artefacts. Use the median of three,
with the edge cache warmed first.
