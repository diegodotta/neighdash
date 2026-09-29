# What NeighDash can and can't do

Talk this through with the user before migrating, not after. Most "a static site
can't do X" objections are solvable. A few limits are real, and they are about
ownership and scale, not features.

## Solvable (with the usual answer)

| People say | The answer |
|---|---|
| "Several people edit the site" | Git already handles concurrent edits, review and history, better than a CMS does. For people who don't use git, a git-based editor gives them a web UI that commits to the repo (Decap, Sveltia, Pages CMS). |
| "We need comments" | Giscus (GitHub Discussions, no backend), or a small Worker with D1 and Turnstile against spam. |
| "We schedule posts" | The build skips posts dated in the future. A daily Workers Cron Trigger or GitHub Action calls the Worker's Deploy Hook, and whatever is due goes live. |
| "We need search" | Pagefind: a build-time index searched in the browser. Fine into the thousands of pages. |
| "Contact form" | A form service, or a Worker with Turnstile that sends the message on. |
| "Newsletter signup" | The newsletter provider's embed or form endpoint. |
| "SEO plugin" | Sitemaps, canonical tags, OpenGraph and structured data come from the build. Redirects go in `_redirects`. |
| "We change things all the time" | A build takes about a minute. Fine for a few changes a day. |

## Real limits

**1. Every dynamic feature becomes code someone owns.** This is the big one.
WordPress's real product is its plugin ecosystem: someone else builds, maintains and
patches each feature. Here each one (comments, forms, anything with state) is a Worker
the owner or their agent writes, with its own spam, security updates and backups.
Great for one or two features. It adds up fast past that.

**2. Publishing is a deploy.** A typo fix is a full build plus the cache. The deploy
gate that protects the site also blocks content: if the build fails for any reason, the
typo waits too. Sites that publish many times an hour (news, live coverage) feel it in
build minutes (3,000 a month on the free plan) and in latency.

**3. "Rebuild everything" has ceilings.** 20,000 files per Worker version on the free
plan, and every image becomes several files (WebP, two sizes, maybe a social card).
Build time grows with the page count against a 20-minute timeout. Git keeps every image
forever, so large media libraries end up in R2, which is one more moving part.

**4. Invisible state.** Redirect rules, build triggers, path routes and secrets live
in Cloudflare, not in git. Document each one in the handoff doc, or manage the zone as
code (Terraform) if the setup keeps growing.

**5. A custom build has a bus factor.** A hand-written build script is software only
its author (and their agent) knows. An established generator (Hugo, Eleventy, Astro)
has docs, a community and upgrade paths. Pick deliberately.

**6. Who can edit, not how many.** Owners who don't use git lose the ability to edit
their own site unless they get a git-based editor. In practice the person who migrated
it often becomes their CMS. Say so before migrating a site for someone else.

**7. Portability is partial.** The build folder is plain files any host can serve.
The Worker, `run_worker_first`, the `_redirects` and `_headers` syntax and zone rules
are Cloudflare-specific.

**8. Some sites are apps.** Logins, member-only content, paywalls, carts and checkout
mean building an application. Keep a proper platform for those, or put the static
pages next to it (a store on its own subdomain, for example).

## The plugin map

Before converting, list the site's active plugins (`wp-extract.sh` prints them) and
decide each one with the user: rebuilt statically, replaced by a service, handled by a
Worker, or dropped. Anything in the "app" column is a reason to stop and talk.

| Plugin kind | Usually becomes |
|---|---|
| SEO (Yoast, Rank Math) | Build output: sitemap, meta tags, structured data. Old sitemap URLs 301 to the new one. |
| Redirects | `_redirects` (path-only) or the Worker (host, query, file-exists logic) |
| Caching, image optimisation, lazy loading | Nothing: pre-built files, WebP at build time, native `loading="lazy"` |
| Security (Wordfence and friends) | Nothing: there is no login or PHP left to attack |
| Search | Pagefind |
| Forms | A form service, or Worker plus Turnstile |
| Comments | Giscus, or Worker plus D1 |
| Newsletter | The provider's embed |
| Analytics | The same tag in the template, or Cloudflare Web Analytics |
| Galleries, sliders, page builders | Static markup from the rendered page, a little JS if needed |
| Data importers (JSON, feeds) | A build-time fetch, or a Worker splice with HTMLRewriter (traps.md 23) |
| Membership, LMS, WooCommerce, bookings | An app. Not NeighDash. |
