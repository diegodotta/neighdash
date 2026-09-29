# NeighDash, a Stable Site Generator 🐴

Cloudflare moved its blog to a CMS called [EmDash](https://blog.cloudflare.com/cloudflare-blog-uses-emdash/).
I moved eight websites off a shared server that kept falling over, with no CMS at
all, and called it NeighDash (neigh sounds like nay, so still no dash, no em dashes
in the writing and no dashboard to log into). The whole story is
[on my blog](https://diego.horse/cloudflare-built-emdash-i-built-neighdash/).

This repo is the part you can reuse: a [Claude Code](https://claude.com/claude-code)
skill with the playbook, the traps, the templates and the scripts, so your agent can
do the same migration without learning every lesson the hard way.

## What you end up with

- Your site as pre-built files, served by Cloudflare's free plan. No database, no
  PHP, no plugin updates, no server of your own.
- Every old URL still working, including the `?p=` shortlinks and old image links
  that Google Images and other sites point at.
- A deploy that refuses to publish when something is wrong, and a route check that
  proves the redirects on Cloudflare's real router.
- A before and after report (Lighthouse and a deliberately honest carbon estimate).

It fits sites that mostly exist to be read: blogs, portfolios, small business
sites. Several editors, comments, scheduled posts and search all have static
answers. The real trade is ownership: WordPress plugins are maintained by someone
else, while here every dynamic feature becomes code you (or your agent) own, and
publishing means a deploy. Logins, paywalls and shops are apps, not NeighDash.
The full list, with a plugin-by-plugin map, is in
[references/limits.md](skills/neighdash/references/limits.md).

## Install

In Claude Code:

```
/plugin marketplace add diegodotta/neighdash
/plugin install neighdash@neighdash
```

Then ask something like *"migrate example.com off WordPress to Cloudflare with
NeighDash"*. The skill loads on its own when the task fits.

Without the plugin system, copy `skills/neighdash/` to `~/.claude/skills/neighdash/`.
Using a different agent? The playbook is plain Markdown in
[skills/neighdash/references](skills/neighdash/references). Hand it the
[prompt from the post](https://diego.horse/cloudflare-built-emdash-i-built-neighdash/#want-to-try-it)
plus those files.

## What's inside

```
skills/neighdash/
  SKILL.md                 the entry point your agent reads
  references/playbook.md   the procedure, step by step
  references/traps.md      30 things that went wrong on real migrations, and the fix
  references/limits.md     what's solvable, what's a real limit, and a plugin map
  references/cloudflare.md API recipes: cutover with rollback, www rule, bot settings, usage
  templates/               wrangler configs, ignores, _headers, _redirects, Worker, probe
  scripts/                 scaffold, extract, gates, route check, QA, Lighthouse, report
```

You'll need `git`, the GitHub CLI, Node.js, Python 3 and Chrome, plus a free
Cloudflare account. For DNS and zone settings, the agent needs Cloudflare's MCP
server (`claude mcp add --transport http cloudflare https://mcp.cloudflare.com/mcp`,
then restart the session) or a scoped API token.

## Honest small print

Tested on my eight sites, which are small (the biggest has 251 posts). The limits
quoted were checked in September 2026 and Cloudflare changes them. It's provided as
is, under the MIT license. Issues and pull requests are welcome, fast replies are
not promised.

Made by [Diego Dotta](https://diego.horse), riding horses, not unicorns.
