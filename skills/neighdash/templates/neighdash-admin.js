/*
 * NeighDash admin bar: publish, unpublish and re-date posts from the local preview.
 * Load it only in preview builds, next to the preview banner:
 *
 *   <script src="/neighdash-admin.js" defer data-live="example.com"></script>
 *
 * and have the preview build write /neighdash-pages.json, mapping each page to the
 * Markdown file it comes from: { "/hello-world/": "content/posts/hello-world.md" }.
 *
 * It only runs on localhost, and only shows up when scripts/edit-server.py answers
 * (data-edit, default this page's port + 3, e.g. 8790 for 8787). Then it takes the place of the yellow
 * preview bar, with the same reminder that this is a preview. Its buttons edit the
 * post's front matter and rebuild the preview. Nothing is committed or deployed.
 * scripts/check-dist.py refuses to deploy a build that loads this file.
 */
(function () {
  var script = document.currentScript;
  var host = location.hostname;
  if (!/^(localhost|127\.0\.0\.1|\[::1\]|::1)$/.test(host)) return;   // never on a real site

  // The edit server listens on this preview's port + 3 (preview.sh starts it that way).
  var EDIT = ((script && script.getAttribute("data-edit")) ||
    "http://localhost:" + ((+location.port || 80) + 3)).replace(/\/$/, "");
  var live = ((script && script.getAttribute("data-live")) || "").replace(/^www\./, "");
  var H = { "X-NeighDash": "1" };

  function path(p) {   // /a/index.html, /a and /a/ are the same page
    p = decodeURI(p).replace(/index\.html$/, "");
    return p.endsWith("/") ? p : p + "/";
  }
  function getJSON(url, opts) {
    return fetch(url, opts).then(function (r) {
      return r.json().then(function (j) { if (!r.ok) throw new Error(j.error || r.status); return j; });
    });
  }

  var pages = {};
  fetch("/neighdash-pages.json", { cache: "no-store" })
    .then(function (r) { return r.ok ? r.json() : {}; })
    .catch(function () { return {}; })
    .then(function (map) {
      Object.keys(map).forEach(function (u) { pages[path(u)] = map[u]; });
      var file = pages[path(location.pathname)] || "";
      return getJSON(EDIT + "/__neighdash/state?file=" + encodeURIComponent(file), { headers: H });
    })
    .then(render)
    .catch(function () {});   // no edit server: the plain preview banner stays

  function urlFor(file) {
    for (var u in pages) if (pages[u] === file) return u;
    return null;
  }

  function render(state) {
    var old = document.getElementById("neighdash-preview-bar");
    if (old) old.remove();
    var hostEl = document.createElement("div");
    hostEl.id = "neighdash-admin";
    var root = hostEl.attachShadow({ mode: "open" });   // the site's CSS can't reach in here
    var page = state.page, isDraft = page && page.draft;
    root.innerHTML = "<style>" +
      ":host{all:initial;position:sticky;top:0;z-index:2147483647;display:block}" +
      ".bar{display:flex;flex-wrap:wrap;gap:8px 14px;align-items:center;justify-content:center;padding:8px 16px;" +
      "font:14px/1.4 system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;background:#ffd400;color:#111;box-shadow:0 2px 0 #111}" +
      ".bar.pub{background:#1b1d20;color:#eee;box-shadow:0 2px 0 #000}" +
      "a{color:inherit}button,input{font:inherit;color:inherit;background:transparent;border:1px solid currentColor;border-radius:6px;padding:2px 9px}" +
      "button{cursor:pointer;white-space:nowrap}button.main{background:#111;color:#ffd400;border-color:#111}" +
      ".pub button.main{background:#eee;color:#111;border-color:#eee}input{color-scheme:light;background:#fff8cc}" +
      ".pub input{color-scheme:dark;background:#2a2d31}button:disabled{opacity:.5;cursor:progress}" +
      ".sep{width:1px;height:18px;background:currentColor;opacity:.3}.quiet{opacity:.75}" +
      "form{display:inline-flex;gap:6px;margin:0}" +
      ".panel{display:none;max-height:50vh;overflow:auto;padding:6px 16px 12px;background:#fff8cc;color:#111;" +
      "font:14px/1.4 system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;border-bottom:2px solid #111}" +
      ".panel.open{display:block}.panel li{display:flex;gap:10px;align-items:center;justify-content:space-between;padding:6px 0;border-top:1px solid #e8dc9a}" +
      ".panel ul{list-style:none;margin:0 auto;padding:0;max-width:760px}.panel small{opacity:.7}" +
      "</style>";
    var bar = document.createElement("div");
    bar.className = "bar" + (page && !isDraft ? " pub" : "");
    bar.setAttribute("role", "region");
    bar.setAttribute("aria-label", "Preview tools");
    var html = "<strong>🧪 Preview on your computer.</strong> <span class=quiet>Your real site hasn't changed.</span>" +
      "<button type=button data-act=drafts>Drafts (" + state.drafts.length + ")</button>";
    if (page) {
      html += "<span class=sep></span><strong>" + (isDraft ? "Draft" : "Published") + "</strong>";
      html += isDraft
        ? "<button type=button class=main data-act=publish>Publish</button><button type=button data-act=publish data-today=1>Publish dated today</button>"
        : "<button type=button data-act=unpublish>Unpublish</button>";
      html += "<form><input type=datetime-local aria-label='Post date'><button type=submit>Save date</button></form>";
      if (state.editor !== "none") html += "<a data-open>Open in " + (state.editor === "cursor" ? "Cursor" : "VS Code") + "</a>";
      if (live && !isDraft) html += "<a target=_blank rel=noopener href='https://" + live + location.pathname + "'>Live page ↗</a>";
    }
    bar.innerHTML = html;
    if (page) {
      bar.querySelector("input").value = page.date || "";
      var open = bar.querySelector("[data-open]");
      if (open) open.href = (state.editor === "cursor" ? "cursor" : "vscode") + "://file" + page.abs;
    }
    var panel = document.createElement("div");
    panel.className = "panel";
    var list = document.createElement("ul");
    state.drafts.forEach(function (d) {
      var li = document.createElement("li");
      var u = urlFor(d.file);
      var t = document.createElement(u ? "a" : "span");
      if (u) t.href = u;
      t.textContent = d.title;
      var meta = document.createElement("small");
      meta.textContent = " " + d.file;
      var left = document.createElement("span");
      left.append(t, meta);
      var b = document.createElement("button");
      b.type = "button"; b.className = "main"; b.textContent = "Publish";
      b.dataset.act = "publish"; b.dataset.file = d.file; b.dataset.title = d.title;
      li.append(left, b);
      list.appendChild(li);
    });
    if (!state.drafts.length) list.innerHTML = "<li>No drafts.</li>";
    panel.appendChild(list);
    root.append(bar, panel);

    function save(body, el) {
      root.querySelectorAll("button").forEach(function (x) { x.disabled = true; });
      getJSON(EDIT + "/__neighdash/edit", { method: "POST", headers: { "Content-Type": "application/json", "X-NeighDash": "1" }, body: JSON.stringify(body) })
        .then(function (j) {
          if (!j.rebuilt) alert("Saved, but the build failed:\n\n" + j.log);
          reloadWhenBuilt(j.stamp);
        })
        .catch(function (err) {
          alert("Couldn't save: " + err.message);
          root.querySelectorAll("button").forEach(function (x) { x.disabled = false; });
        });
    }
    // wrangler dev picks up the rebuilt files a moment after the build ends. The edit
    // server writes a stamp into the build folder: reload once the preview serves it.
    function reloadWhenBuilt(stamp) {
      if (!stamp) { setTimeout(function () { location.reload(); }, 1000); return; }
      var tries = 0;
      (function poll() {
        fetch("/neighdash-build.txt", { cache: "no-store" })
          .then(function (r) { return r.ok ? r.text() : ""; })
          .catch(function () { return ""; })
          .then(function (t) {
            if (t.trim() === stamp || ++tries > 40) location.reload();
            else setTimeout(poll, 200);
          });
      })();
    }
    root.addEventListener("click", function (e) {
      var b = e.target.closest("button[data-act]");
      if (!b) return;
      var act = b.dataset.act;
      if (act === "drafts") { panel.classList.toggle("open"); return; }
      var file = b.dataset.file || page.file, title = b.dataset.title || page.title, today = !!b.dataset.today;
      var msg = (act === "unpublish" ? "Unpublish" : "Publish") + " “" + title + "”" + (today ? " with today's date" : "") +
        "?\n\nThis only changes " + file + " on this computer and rebuilds the preview. Nothing goes live until it's committed and deployed.";
      if (confirm(msg)) save({ file: file, action: act, today: today }, b);
    });
    root.addEventListener("submit", function (e) {
      e.preventDefault();
      save({ file: page.file, action: "date", date: root.querySelector("input").value });
    });

    document.body.insertBefore(hostEl, document.body.firstChild);
  }
})();
