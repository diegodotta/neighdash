---
name: neighdash
description: Migrate WordPress or other shared-hosting sites to static HTML on Cloudflare Workers static assets (free plan) with no CMS, no server and no downtime. Covers URL inventory, conversion from rendered pages, deploy gates, route checks on the real router, the DNS cutover with automatic rollback, keeping the free daily Worker requests for what needs them, and an honest before/after Lighthouse and carbon report. Use when someone wants to leave WordPress or shared hosting, move a site to Cloudflare Workers or Pages, turn a site into static files, or mentions NeighDash.
license: MIT
---

# NeighDash, a Stable Site Generator

A playbook for moving small and medium sites (blogs, portfolios, landing pages,
small business sites) off WordPress and shared hosting onto pre-built files served
by Cloudflare. Distilled from migrating eight real sites. Most of it is about
not breaking things: every old URL keeps working, nothing private gets published,
and the domain never goes dark.

## Ground rules (agree them with the user before starting)

1. **Ask before anything hard to undo**: DNS changes, zone settings, deleting records
   or rules, merging to the production branch (it deploys), cancelling hosting.
   One yes covers one action, not the rest of the migration.
2. **Work on a `dev` branch.** The production branch is the deploy trigger.
3. **Prove it on the real router.** Routing lives in Cloudflare's config
   (`run_worker_first`, `_redirects`, `not_found_handling`), which unit tests never
   touch. Run `scripts/route-check.sh` on `wrangler dev` and again on the live site.
4. **Keep a handoff doc** (`CONTEXT.md` in the user's workspace): goal, access,
   decisions, per-site status, numbered learnings. No secrets in it.
5. **Measure, then claim.** Lighthouse medians of three runs, the same setup on both
   sides. Screenshots, not status codes, for anything visual.

## The procedure

Follow [references/playbook.md](references/playbook.md) step by step:

0. Handoff doc and ground rules
1. Inventory and baseline, while the old site is still up (Lighthouse "before",
   every URL, access logs, DNS snapshot, mail)
2. Pick the shape per site (lift and shift, rebuild, Markdown plus a build script,
   crawl and clean)
3. Convert with fidelity (from rendered pages, measured, media as WebP)
4. Repo and build (serve a build folder, deploy gate, cache headers)
5. The Worker, only if needed (path-list `run_worker_first`, legacy redirects)
6. Cloudflare project (git-connected, production-branch trigger only)
7. Prove it before touching DNS
8. Cutover, after the user says yes
9. After (report, fixes, mail, decommission)

When something surprises you, check [references/traps.md](references/traps.md)
first. Thirty things that went wrong on real migrations, with the fix. For API
calls (cutover, Redirect Rules, Bot Fight Mode, cache purge, daily Worker usage)
use [references/cloudflare.md](references/cloudflare.md).

## The three traps that matter most

- **The repo root gets published.** Serve `dist/` or `public/`, never `./`, or
  `.git` goes live (traps.md 1).
- **`run_worker_first: true` burns the account's shared 100,000 free Worker
  requests a day on every image and stylesheet.** Use a path list. www to apex is a
  zone Redirect Rule, not Worker code (traps.md 2).
- **With `not_found_handling: "404-page"`, URLs with no file behind them never
  reach the Worker** unless listed in `run_worker_first`. Legacy redirects silently
  turn into 404s (traps.md 3).

## Tools

Scripts are in `${CLAUDE_SKILL_DIR}/scripts/`, templates in
`${CLAUDE_SKILL_DIR}/templates/`. Run scripts from the site's folder.

| Script | Use |
|---|---|
| `new-site.sh <domain> [parent]` | Scaffold a small static site (`public/`, wrangler config, ignores, headers) |
| `wp-extract.sh` | Pages, content, image URLs and `?p=` ID map over SSH with wp-cli (`SSH_TARGET`, `WP_PATH`) |
| `archive-wp.py <host> <path> <outdir> [--origin ip]` | Save an original page with its assets, to compare offline |
| `safety-check.sh [dir]` | Pre-push gate: what gets served, secrets, 25 MiB files |
| `check-dist.py <dist>` | Deploy gate for the build command (edit its SETTINGS) |
| `route-check.sh <routes.txt> <base>` | Every old URL against `wrangler dev` or the live site |
| `qa-check.sh <url>` | Pages, leaks, 404, OpenGraph, analytics |
| `perf-audit.sh <url> [desktop]` | Local Lighthouse with every failing audit (`RUNS=3`) |
| `migration-report.sh <domain> --before/--after/--report` | Before/after Lighthouse, page weight, modelled carbon |
| `pixel-diff.sh <a> <b> <out>` | Screenshot diff of two builds (run a control first) |
| `contrast-check.sh '<fg> on <bg>'` | WCAG contrast and the nearest passing shade |
| `inline-css.sh <dir>` | Inline a small `styles.css` between markers |

| Template | Use |
|---|---|
| `wrangler.static.jsonc` | Files only, no Worker |
| `wrangler.worker.jsonc` | With the legacy-redirect Worker and a narrow `run_worker_first` |
| `worker/legacy-redirects.js` | Old uploads to WebP, `?p=`, `?s=`, `/page/N/`, feeds, sitemaps |
| `worker/probe.js` | Local only: shows which paths still invoke the Worker |
| `www-redirect-rule.json` | The zone Redirect Rule for www to apex |
| `assetsignore.template`, `gitignore.template`, `_headers`, `_redirects.example` | Copy into place |

Requirements: `git`, `gh`, Node.js (for `npx wrangler` and Lighthouse), Python 3,
Chrome. `pixel-diff.sh` also needs ImageMagick. Zone work (DNS, rules, bot
settings) needs the Cloudflare MCP server or a scoped API token: the wrangler login
can deploy Workers but can't change zones.

## What NeighDash is not

Not a CMS and not a site generator framework. It fits sites with one or a few
writers who publish now and then and are happy editing files (or asking an agent
to). A newsroom with many editors, scheduled posts and review flows needs a real
CMS. Say so if that's the user.
