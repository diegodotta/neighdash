#!/usr/bin/env python3
"""
Local edit server for the NeighDash admin bar (templates/neighdash-admin.js).

    edit-server.py [site-dir]          (preview.sh starts it when the site opts in)

Publishing a draft, unpublishing a post or changing its date, from the preview,
without anyone opening a Markdown file. It edits the post's front matter and runs
the site's build. Nothing is committed and nothing is deployed: going live is still
a commit and a deploy, through the agent and the owner's yes.

The site opts in with a `neighdash.json` next to its wrangler.jsonc:

    { "edit": { "content": "content", "build": "python3 build.py --preview" } }

  content   folder (or list of folders) holding the Markdown files it may edit
  build     command that rebuilds the preview after an edit (run in the site folder)
  port      default 8790
  editor    "vscode" (default), "cursor" or "none", for the bar's "Open in editor"

Front matter is YAML between `---` lines, with `draft: true` and `date:`, the shape
Hugo, Eleventy, Astro, Jekyll and most hand-written build scripts use.

Safety: it listens on 127.0.0.1 only, answers only requests that come from a
localhost page with the X-NeighDash header and a localhost Host (so another website
can't trigger it, not even through DNS rebinding), and only touches .md files inside
the content folders. Standard library only.
"""
import datetime as dt, http.server, json, pathlib, re, subprocess, sys, urllib.parse

SITE = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
conf_file = SITE / "neighdash.json"
if not conf_file.is_file():
    sys.exit(f"No neighdash.json in {SITE}. Add one with an \"edit\" section (see this script's header).")
CONF = json.loads(conf_file.read_text()).get("edit") or {}
dirs = CONF.get("content", "content")
CONTENT = [(SITE / d).resolve() for d in ([dirs] if isinstance(dirs, str) else dirs)]
BUILD = CONF.get("build")
PORT = int(CONF.get("port", 8790))
EDITOR = CONF.get("editor", "vscode")
LOCAL = re.compile(r"^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$")
ORIGIN = re.compile(r"^http://(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$")
FRONT = re.compile(r"\A(---[ \t]*\r?\n)(.*?\r?\n)(---[ \t]*\r?\n?.*)\Z", re.S)
DATE = re.compile(r"""^date:[ \t]*(["']?)(\d{4}-\d\d-\d\d)(?:([ T])(\d\d:\d\d)(:\d\d)?)?([^"'\r\n]*)\1[ \t]*$""", re.M)


def content_file(rel: str):
    """The file, if it's a Markdown file inside a content folder, else None."""
    try:
        p = (SITE / rel).resolve()
    except (OSError, ValueError):
        return None
    if p.suffix != ".md" or not p.is_file() or not any(p.is_relative_to(c) for c in CONTENT):
        return None
    return p


def front(p: pathlib.Path):
    m = FRONT.match(p.read_text(encoding="utf-8"))
    return m


def info(p: pathlib.Path) -> dict:
    m = front(p)
    fm = m.group(2) if m else ""
    title = re.search(r"""^title:[ \t]*(["']?)(.*?)\1[ \t]*$""", fm, re.M)
    d = DATE.search(fm)
    return {
        "file": p.relative_to(SITE).as_posix(),
        "abs": p.as_posix(),
        "title": title.group(2) if title else p.stem,
        "draft": bool(re.search(r"^draft:[ \t]*true[ \t]*$", fm, re.M | re.I)),
        "date": f"{d.group(2)}T{d.group(4) or '00:00'}" if d else None,
    }


def drafts() -> list:
    out = []
    for c in CONTENT:
        for p in sorted(c.rglob("*.md")):
            i = info(p)
            if i["draft"]:
                out.append(i)
    return out


def edit(p: pathlib.Path, action: str, data: dict) -> str | None:
    """Apply the action to the front matter. Returns an error, or None."""
    text = p.read_text(encoding="utf-8")
    m = FRONT.match(text)
    if not m:
        return "no front matter"
    fm, is_draft = m.group(2), info(p)["draft"]
    nl = "\r\n" if "\r\n" in fm else "\n"

    def set_date(fm, when):
        d = DATE.search(fm)
        if not d:   # no date yet: add one after the title, or at the top
            line = f'date: "{when:%Y-%m-%d %H:%M:%S}"{nl}'
            t = re.search(r"^title:.*\r?\n", fm, re.M)
            return fm[:t.end()] + line + fm[t.end():] if t else line + fm
        q, sep, secs, tail = d.group(1), d.group(3), d.group(5), d.group(6)
        value = f"{when:%Y-%m-%d}" + (f"{sep}{when:%H:%M}" + (f"{when::%S}" if secs else "") if sep else "") + tail
        return fm[:d.start()] + f"date: {q}{value}{q}" + fm[d.end():]

    if action == "publish":
        if not is_draft:
            return "not a draft"
        fm = re.sub(r"^draft:[ \t]*true[ \t]*\r?\n", "", fm, count=1, flags=re.M | re.I)
        if data.get("today"):
            fm = set_date(fm, dt.datetime.now())
    elif action == "unpublish":
        if is_draft:
            return "already a draft"
        fm = re.sub(r"^draft:.*\r?\n", "", fm, flags=re.M)
        d = DATE.search(fm)
        at = fm.index(nl, d.end()) + len(nl) if d else len(fm)
        fm = fm[:at] + f"draft: true{nl}" + fm[at:]
    elif action == "date":
        try:
            when = dt.datetime.strptime(str(data.get("date")), "%Y-%m-%dT%H:%M")
        except ValueError:
            return "bad date"
        fm = set_date(fm, when)
    else:
        return "unknown action"
    p.write_text(m.group(1) + fm + m.group(3), encoding="utf-8")
    return None


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "neighdash-edit"

    def log_message(self, fmt, *args):   # quiet: only edits get printed
        pass

    def allowed(self) -> bool:
        origin = self.headers.get("Origin", "")
        return (self.client_address[0] in ("127.0.0.1", "::1")
                and bool(LOCAL.match(self.headers.get("Host", "")))
                and bool(ORIGIN.match(origin)))

    def reply(self, code: int, body: dict | None = None):
        out = json.dumps(body or {}).encode()
        self.send_response(code)
        origin = self.headers.get("Origin", "")
        if ORIGIN.match(origin):   # never for another website's page
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Access-Control-Allow-Headers", "Content-Type, X-NeighDash")
            self.send_header("Access-Control-Allow-Methods", "GET, POST")
            self.send_header("Vary", "Origin")
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)

    def do_OPTIONS(self):
        self.reply(204 if self.allowed() else 403)

    def do_GET(self):
        if not self.allowed() or self.headers.get("X-NeighDash") != "1":
            return self.reply(403, {"error": "forbidden"})
        url = urllib.parse.urlparse(self.path)
        if url.path != "/__neighdash/state":
            return self.reply(404, {"error": "not found"})
        rel = (urllib.parse.parse_qs(url.query).get("file") or [""])[0]
        p = content_file(rel) if rel else None
        self.reply(200, {"page": info(p) if p else None, "drafts": drafts(), "editor": EDITOR})

    def do_POST(self):
        if not self.allowed() or self.headers.get("X-NeighDash") != "1":
            return self.reply(403, {"error": "forbidden"})
        if self.path != "/__neighdash/edit":
            return self.reply(404, {"error": "not found"})
        try:
            data = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        except ValueError:
            return self.reply(400, {"error": "bad request"})
        p = content_file(str(data.get("file", "")))
        if not p:
            return self.reply(403, {"error": "not a Markdown file in the content folder"})
        err = edit(p, str(data.get("action")), data)
        if err:
            return self.reply(409, {"error": err})
        rebuilt, log = True, ""
        if BUILD:
            r = subprocess.run(BUILD, shell=True, cwd=SITE, capture_output=True, text=True, timeout=600)
            rebuilt, log = r.returncode == 0, (r.stdout + r.stderr)[-800:]
        print(f"  {data.get('action')}: {p.relative_to(SITE)}" + ("" if rebuilt else "  (the build failed)"), flush=True)
        self.reply(200, {"ok": True, "rebuilt": rebuilt, "log": log})


if __name__ == "__main__":
    missing = [c for c in CONTENT if not c.is_dir()]
    if missing:
        sys.exit(f"Content folder not found: {missing[0]}")
    srv = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"Edit server on http://127.0.0.1:{PORT} (this computer only), editing {', '.join(c.relative_to(SITE).as_posix() for c in CONTENT)}", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
