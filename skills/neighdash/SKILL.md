---
name: neighdash
description: Migrate WordPress or other shared-hosting sites to static HTML on Cloudflare Workers static assets (free plan) with no CMS, no server and no downtime. Covers the fit check, URL inventory, conversion from rendered pages, deploy gates, route checks on the real router, moving DNS and email safely, the cutover with automatic rollback, keeping the free daily Worker requests for what needs them, and an honest before/after Lighthouse and carbon report. Works with technical and non-technical site owners. Use when someone wants to leave WordPress or shared hosting, move a site to Cloudflare Workers or Pages, turn a site into static files, or mentions NeighDash.
license: MIT
---

# NeighDash, a Stable Site Generator

A playbook for moving small and medium sites (blogs, portfolios, landing pages,
small business sites) off WordPress and shared hosting onto pre-built files served
by Cloudflare. Distilled from migrating eight real sites. Most of it is about
not breaking things: every old URL keeps working, nothing private gets published,
email keeps arriving, and the domain never goes dark.

**Paths:** scripts are in `${CLAUDE_SKILL_DIR}/scripts/`, templates in
`${CLAUDE_SKILL_DIR}/templates/`. If `CLAUDE_SKILL_DIR` is empty (the repo was cloned
rather than installed as a plugin), the skill folder is the directory that contains
this SKILL.md.

## 1. Is it the right fit? (ask first)

Before anything else, find out:

- **Does the site take orders, payments, bookings or logins?** Shops, memberships and
  booking systems are apps, not NeighDash. Keep them on a proper platform (the
  static site can link to it or live beside it) or stop here.
- **WordPress.com or their own hosting?** WordPress.com has no SSH or server logs and
  often runs the domain's DNS and email too (see playbook step 1). Self-hosted
  WordPress on cPanel-style hosting is the common case.
- **Where does their email live?** At the web host, Google Workspace, Microsoft 365,
  or nowhere. Mail at the web host is the riskiest part of the whole migration.
- **Who edits the site, and how often?** Owners who don't use git lose WordPress's
  editor. Say so now, not after.

Then read [references/limits.md](references/limits.md) with them: what's solvable
(multiple editors, comments, scheduled posts, search, forms) and the real limits
(every dynamic feature becomes owned code, publishing is a deploy, scale ceilings,
who can edit). Map the old site's plugins with the plugin map there.

## 2. If the owner isn't technical

Many people arrive with one sentence ("help me move my site with NeighDash"). Then
you do the typing and they make the decisions.

- **Start with the plan in plain words:** what changes (where the site lives), what
  stays (their address, their email, their content, every old link), what it costs
  (Cloudflare's free plan, a possible $5 a month later, plus an email provider if
  their mail lives at the web host), how long, and what you'll need from them.
- **Real time ranges** from the eight migrations behind this skill: a small site took
  one or two working sessions, a blog with a few hundred posts took several over a
  week or two, and moving the domain's DNS can take up to a day to settle.
- **Translate the jargon the first time it comes up:**

  | Say | Means |
  |---|---|
  | the domain's address book | DNS |
  | who keeps the address book | nameservers |
  | where your email gets delivered | MX records |
  | publish the new version | merge to the production branch |
  | a preview on your computer | `http://localhost:8787` from `scripts/preview.sh` |
  | a private preview link | the workers.dev URL |

- **Check the computer first**, without changing anything: `git`, `gh`, Node.js,
  Python 3, and Chrome (only needed for the Lighthouse reports). Say which are missing
  and why, and ask before installing. Warn them up front: installing `git` on a Mac
  opens an Apple pop-up (Command Line Tools), and Homebrew asks for the Mac's password
  **typed into Terminal**, never into the chat. The official installers (git-scm.com,
  nodejs.org, python.org) are a gentler alternative.
- **One account at a time:** GitHub, then Cloudflare. Walk them through signing up,
  then log in through the browser (`gh auth login --web`, `npx wrangler login`).
  **Never ask anyone to paste a password, API token or private key into the chat.**
- **Use the access they already have.** No SSH? WordPress's Tools, Export gives every
  post with its ID. A crawl of the live site gives the rendered pages. cPanel's Zone
  Editor exports the DNS records and "Raw Access" gives the access logs, both
  downloaded by the owner.
- **Before every step that could break something,** say what will happen, how long it
  takes, what they'll notice, and how to undo it. Then wait for a yes.
- **Show before switching, twice.** First on their computer (`scripts/preview.sh`),
  then on the online preview. Every page carries a yellow bar
  (`templates/preview-banner.js`) that says it's a preview and that the real site
  hasn't changed, because a non-technical owner can't tell localhost from the
  internet. Tell them what the bar means, then walk them through the checklist in
  playbook step 7. Their "looks right" comes before any cutover question.
- **End with a one-page note in plain words:** where the site lives now, how to change
  a page (ask an agent, or edit on GitHub), that `/wp-admin` no longer exists, what
  renews when (domain, email), and what to do if something looks wrong.

## 3. Ground rules (agree them with the user)

1. **Ask before anything hard to undo**: DNS and nameserver changes, zone settings,
   deleting records or rules, publishing (merging to the production branch deploys),
   cancelling hosting. One yes covers one action, not the rest of the migration.
2. **Work on a `dev` branch.** The production branch is the deploy trigger.
3. **Prove it on the real router.** Routing lives in Cloudflare's config
   (`run_worker_first`, `_redirects`, `not_found_handling`), which unit tests never
   touch. Run `scripts/route-check.sh` on `wrangler dev` and again on the live site.
4. **Keep a handoff doc** (`CONTEXT.md` in the user's workspace): goal, access,
   decisions, per-site status, numbered learnings. No secrets in it. Update it before
   anything that restarts the session (adding an MCP server does).
5. **Email is sacred.** Never delete or repoint a record mail depends on without a mail
   test before and after.
6. **Measure, then claim.** Lighthouse medians of three runs, the same setup on both
   sides. Screenshots, not status codes, for anything visual.

## 4. The procedure

Follow [references/playbook.md](references/playbook.md) step by step:

0. Handoff doc and ground rules
1. Inventory and baseline, while the old site is still up (Lighthouse "before", every
   URL, access logs, DNS snapshot, plugins, mail)
2. Pick the shape per site (lift and shift, rebuild, Markdown plus a build script,
   crawl and clean)
3. Convert with fidelity (from rendered pages, measured, media as WebP)
4. Repo and build (serve a build folder, deploy gate, cache headers)
5. The Worker, only if needed (path-list `run_worker_first`, legacy redirects)
6. Cloudflare: zone access, moving the DNS (DNSSEC first), the project
7. Prove it before touching the site's records, then freeze WordPress edits
8. Cutover, after the user says yes (mail dependencies checked first)
9. After (report, fixes, email, lock down and retire the old install)

When something surprises you, check [references/traps.md](references/traps.md)
first: real things that went wrong, with the fix. API calls (cutover, Redirect Rules,
Bot Fight Mode, cache purge, daily Worker usage) are in
[references/cloudflare.md](references/cloudflare.md).

## 5. The traps that matter most

- **Mail pointing at the website's address.** On typical cPanel hosts the MX record,
  `mail.` and `webmail.` point at the domain itself and SPF trusts `a`/`mx`. Delete the
  apex record at cutover and email silently stops (traps.md 31).
- **DNSSEC at the registrar.** Change nameservers with DNSSEC on and the domain stops
  resolving for many visitors, email included (traps.md 32).
- **The repo root gets published.** Serve `dist/` or `public/`, never `./`, or `.git`
  goes live (traps.md 1).
- **`run_worker_first: true` burns the account's shared 100,000 free Worker requests a
  day on every image and stylesheet.** Use a path list. www to apex is a zone Redirect
  Rule, not Worker code (traps.md 2).
- **With `not_found_handling: "404-page"`, URLs with no file behind them never reach
  the Worker** unless listed in `run_worker_first`. Legacy redirects silently turn
  into 404s (traps.md 3).

## 6. Tools

Run scripts from the site's folder.

| Script | Use |
|---|---|
| `new-site.sh <domain> [parent]` | Scaffold a small static site (`public/`, wrangler config, ignores, headers) |
| `wp-extract.sh` | Plugins, pages, content, image URLs and `?p=` ID map over SSH with wp-cli (`SSH_TARGET`, `WP_PATH`) |
| `archive-wp.py <host> <path> <outdir> [--origin ip]` | Save an original page with its assets, to compare offline |
| `safety-check.sh [dir]` | Pre-push gate: what gets served, secrets, 25 MiB files |
| `check-dist.py <dist>` | Deploy gate for the build command (edit its SETTINGS) |
| `preview.sh [dir]` | Run the site on this computer the way Cloudflare will, and open it |
| `routes-from-sitemap.py <domain>` | Write a starting `routes.txt` from the old site's sitemap |
| `route-check.sh <routes.txt> <base>` | Every old URL against the local preview or the live site |
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
| `preview-banner.js` | The yellow "this is a preview" bar, silent on the real domain |
| `www-redirect-rule.json` | The zone Redirect Rule for www to apex |
| `assetsignore.template`, `gitignore.template`, `_headers`, `_redirects.example` | Copy into place |

**Access, in order of preference.** The wrangler login deploys Workers but can't
change zones. For DNS, rules and bot settings, use the Cloudflare MCP server
(`claude mcp add --transport http cloudflare https://mcp.cloudflare.com/mcp`, log in
through the browser, then restart the session: update CONTEXT.md first and tell the
owner the conversation will restart). If a token is unavoidable, the owner creates a
scoped one in the Cloudflare dashboard and saves it to a file only they write
(`~/.config/neighdash/cloudflare-token`, `chmod 600`). Read it from there, never print
it, never ask for it in the chat.
