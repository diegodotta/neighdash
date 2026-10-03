# NeighDash, a Stable Site Generator 🐴

Cloudflare moved its blog to a CMS called [EmDash](https://blog.cloudflare.com/cloudflare-blog-uses-emdash/).
I moved eight websites off a shared server that kept falling over, with no CMS at
all, and called it NeighDash (nay CMS, nay dashboard, nay logins, nay database, nay headaches). The whole story is
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
- Optionally, for Markdown blogs: publish, unpublish and re-date posts from a bar on
  the preview on your own computer, without opening a file. Nothing goes live until
  it's deployed.

It fits sites that mostly exist to be read: blogs, portfolios, small business
sites. Several editors, comments, scheduled posts and search all have static
answers. The real trade is ownership: WordPress plugins are maintained by someone
else, while here every dynamic feature becomes code you (or your agent) own, and
publishing means a deploy. Logins, paywalls and shops are apps, not NeighDash.
The full list, with a plugin-by-plugin map, is in
[references/limits.md](skills/neighdash/references/limits.md).

## Start here

**Not technical?** Open [Claude Code](https://claude.com/claude-code) (the desktop app
is the friendliest way in) and paste this, with your own address:

```text
Help me move my website example.com off WordPress and onto Cloudflare using NeighDash (https://github.com/diegodotta/neighdash). I'm not technical. Read the repo's skills/neighdash/SKILL.md first, explain each step in plain words before doing it, do the typing for me, and ask me before anything that could take my site or my email down.
```

It will still need you for what only a human can do: creating free GitHub and
Cloudflare accounts, clicking "allow" when a login pops up, typing your computer's
password if it installs a missing tool, and saying yes before anything that touches
your domain or your email. It never needs your passwords in the chat.

Before anything changes for your visitors, you'll see the new site twice: first on
your own computer, then on a private Cloudflare address. Both carry a yellow bar at
the top saying it's a preview and that your real site hasn't changed, so you always
know which one you're looking at. Your real address never shows the bar. If your email
lives at your web host today, it will also need a new home (a few dollars a month per
mailbox), and the skill walks you through that before anything is cancelled.

## Install

Already using Claude Code? Install the skill so it loads on its own:

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
  references/traps.md      34 things that go wrong on real migrations, and the fix
  references/limits.md     what's solvable, what's a real limit, and a plugin map
  references/cloudflare.md API recipes: cutover with rollback, www rule, bot settings, usage
  templates/               wrangler configs, ignores, _headers, _redirects, Worker, probe,
                           the preview bar and the preview's admin bar
  scripts/                 scaffold, extract, local preview and edit server, gates,
                           route checks, QA, report
tests/selftest.sh          checks the whole kit (run it after changing anything)
```

You'll need `git`, the GitHub CLI, Node.js, Python 3.9 or newer (the one macOS ships is
fine) and Chrome, plus a free
Cloudflare account. For DNS and zone settings, the agent needs Cloudflare's MCP
server (`claude mcp add --transport http cloudflare https://mcp.cloudflare.com/mcp`,
then restart the session) or a scoped API token.

## Changing the skill

Run `tests/selftest.sh` after any change. It checks every script's syntax, the plugin
structure, the scaffold and both deploy gates (including the cases they must
refuse), the Worker template against 21 legacy URLs on Cloudflare's own router,
which paths run the Worker, the local preview, and the edit server (including the
requests it must refuse). `ONLINE=1` also reads a real
sitemap.

## What's next

Starting a new blog from scratch, with a home page, posts, About, a menu and a footer
ready to write in. The plan is in [ROADMAP.md](ROADMAP.md).

## Honest small print

Tested on my eight sites, which are small (the biggest has 251 posts). The limits
quoted were checked in September 2026 and Cloudflare changes them. It's provided as
is, under the MIT license. Issues and pull requests are welcome, fast replies are
not promised.

Made by [Diego Dotta](https://diego.horse), riding horses, not unicorns.
