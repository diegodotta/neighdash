# Roadmap

Where NeighDash is heading. Nothing here has a date. Each item gets built and tested on
a real site first (usually [diego.horse](https://diego.horse)) and only then lands in
the kit. Ideas and pull requests are welcome.

## 0.2: Edit from the preview

**Status: done in 0.2.0.** Set up per site in playbook step 4.

A static site has no admin panel, and that's mostly the point. But small chores, like
publishing a draft or fixing a date, shouldn't need anyone to open a Markdown file. So
the local preview gets an admin bar across the top of every page:

- the drafts, with how many there are, each with its own **Publish** button
- on a post: Draft or Published, then **Publish**, **Publish dated today** or **Unpublish**
- a date field to re-date a post
- **Open in editor** for the post's file, and a link to the live page

The buttons only edit the post's front matter on your own computer and rebuild the
preview. Nothing is committed or deployed, so going live still goes through the agent
and your approval, like every other deploy.

To work with whatever generator a site uses, it comes as:

- a small local edit server (`scripts/edit-server.py`), started by `scripts/preview.sh`,
  that accepts requests from this computer only, with a custom header so other
  websites can't trigger it
- an admin bar script (`templates/neighdash-admin.js`) that takes the place of the
  yellow preview bar, and reads a small JSON file the preview build writes: which page
  comes from which file
- a rule in `scripts/check-dist.py` that refuses to deploy if the bar ever reaches the
  built site, plus self-test cases for all of it

## 0.3: A front door

**Status: next.** From the first real run of 0.2: it worked, but it felt like a
developer tool. The permission prompts were the scary part, with no clear reason
for each one.

- **Start with a welcome and one plain choice:** move an old site, start a new
  blog, or put a folder of files online. Offered as clickable options where the app
  supports them, not as a question to type an answer to.
- **Accounts first, as a checklist the agent verifies:** GitHub, then Cloudflare,
  one at a time with links, checked by the agent itself (logged in or not) instead of
  coming up halfway through.
- **A plain progress line:** "Step 2 of 5: getting your accounts ready", so the owner
  always knows where they are and what's left.
- **Fewer permission prompts, and a reason for each:**
  - A suggested project settings file that pre-approves the safe, read-only commands
    (looking at files, checking the preview, running the checks), offered once, with
    the list shown in plain words.
  - Before anything that still needs a yes, one sentence on why it's needed and what
    it changes.
  - Group related steps so one yes covers one clearly described action, instead of a
    yes per command.
- **No browser automation unless it's needed.** Checking the preview works with
  plain requests. Screenshots or driving Chrome only come in at the visual review
  step, explained first, or when the owner asks.
- **Test it the way an owner would:** in the Claude desktop app, starting from one
  plain sentence, with nothing set up.

## 0.4: Start from scratch

**Status: idea.**

Today NeighDash moves an existing site. The skill could also ask, at the very start,
*"moving an existing site, or starting a new one?"*, and for a new one set up a
small blog that's ready to write in:

- a home page, a posts archive, an About page, a menu and a footer, all set from one
  small config file
- Markdown posts with drafts, tags and images
- RSS, a sitemap and search out of the box
- a minimal theme of its own, with system fonts and light and dark modes
- the same deploy gate, route checks and preview (with the 0.2 admin bar) as a migrated
  site

The admin bar is what makes this work for people who don't want to touch files, and
the front door is how they get here, which is why both come first.

## More admin bar ideas

- **New post**: start a draft from the bar, with today's date
- **Rebuild**: for when a file changed outside the bar
- **Syndication status**: where a post was cross-posted (dev.to, Medium...) and what's
  still pending
- **Changes not yet live**: how many edits aren't committed yet, so nothing gets
  forgotten before a deploy

## For the playbook

Lessons from bringing old content back into a migrated blog, to add to
`references/playbook.md` and `references/traps.md`:

- **Recovering content from dead platforms.** Old blogs on free hosts (UOL, Multiply,
  photo communities) often survive only in the Wayback Machine. Its CDX search finds
  every archived page of a host, but it rate-limits hard, so queries need to be paced.
  Some communities moved to a successor site that still hosts the originals. The
  archive usually keeps the text and loses the photos.
- **Matching a photo backup to the albums it came from.** Original file names often
  survive on the archived album pages. Where they don't, the edit date in each photo
  tends to match the day an album was posted. Two cameras can produce the same file
  name (`PICT0096.jpg` twice), so check every match by eye.
- **Posts made only of galleries get no share card** when the card falls back to the
  first standalone figure. Fall back to the first gallery photo too.
- **GIFs never get a share card**, since social networks want JPEG or PNG. Make one from
  the first frame.
- **Quote blocks that never close.** A WordPress-to-Markdown conversion can turn an
  aside or a quoted line into a quote that swallows the rest of the post, including any
  embed inside it. Compare the converted post with the original.
- **Floated images lose their float** once WordPress's CSS is gone. Small covers and
  portraits that used to sit beside the text need a new layout, like centered at their
  original width.
- **Photo notes and comments belong in the lightbox.** Long lists of comments under a
  gallery bury the photos. Keep each photo's details hidden on the page and show them
  when the photo opens full screen.
