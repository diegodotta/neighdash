/*
 * NeighDash preview banner. Put it at the site root and load it on every page:
 *
 *   <script src="/preview-banner.js" defer data-live="example.com"></script>
 *
 * On the real domain (example.com or www.example.com) it does nothing. Anywhere
 * else a site owner might look at the new site before it goes live, it shows a bar
 * across the top so nobody mistakes a preview for the real thing:
 *   - on their own computer (localhost), from scripts/preview.sh
 *   - on the temporary Cloudflare address (*.workers.dev, *.pages.dev)
 * Any other host (a mirror, an archive) gets nothing.
 */
(function () {
  var script = document.currentScript;
  var live = ((script && script.getAttribute("data-live")) || "").toLowerCase().replace(/^www\./, "");
  var host = location.hostname.toLowerCase();
  if (live && (host === live || host === "www." + live)) return;

  var local = location.protocol === "file:" || host === "localhost" || host === "127.0.0.1" || host === "[::1]" || host === "::1";
  var cloudflare = /\.(workers|pages)\.dev$/.test(host);
  if (!local && !cloudflare) return;

  var title = local ? "Preview on your computer." : "Private preview.";
  var before = local
    ? " Only you can see this page. It is not on the internet, and your real site"
    : " This is the new site on a temporary Cloudflare address. Your real site";
  var after = local ? " hasn't changed." : " hasn't changed yet.";

  try { if (sessionStorage.getItem("neighdash-preview-hidden")) return; } catch (e) {}
  if (document.title.indexOf("PREVIEW") !== 0) document.title = "PREVIEW · " + document.title;

  var bar = document.createElement("div");
  bar.id = "neighdash-preview-bar";   // neighdash-admin.js takes its place when editing is on
  bar.setAttribute("role", "note");
  bar.style.cssText = "position:sticky;top:0;z-index:2147483647;display:flex;gap:12px;align-items:center;" +
    "justify-content:center;padding:10px 44px 10px 16px;background:#ffd400;color:#111;" +
    "font:15px/1.4 system-ui,-apple-system,'Segoe UI',Roboto,sans-serif;text-align:center;" +
    "box-shadow:0 2px 0 #111;";
  var label = document.createElement("span");
  label.innerHTML = "<strong>" + (local ? "🧪 " : "👀 ") + title + "</strong>";
  label.appendChild(document.createTextNode(before));
  if (live) {
    var domain = document.createElement("span");
    domain.style.whiteSpace = "nowrap";   // don't split the address at its hyphens
    domain.textContent = " " + live;
    label.appendChild(domain);
  }
  label.appendChild(document.createTextNode(after));
  var close = document.createElement("button");
  close.type = "button";
  close.setAttribute("aria-label", "Hide the preview bar for now");
  close.textContent = "×";
  close.style.cssText = "position:absolute;right:10px;top:50%;transform:translateY(-50%);border:0;" +
    "background:transparent;color:#111;font:22px/1 system-ui,sans-serif;cursor:pointer;padding:4px 8px;";
  close.onclick = function () {
    bar.remove();
    try { sessionStorage.setItem("neighdash-preview-hidden", "1"); } catch (e) {}
  };
  bar.appendChild(label);
  bar.appendChild(close);

  function show() {
    if (document.getElementById("neighdash-admin")) return;   // the admin bar already says it
    document.body.insertBefore(bar, document.body.firstChild);
  }
  if (document.body) show(); else document.addEventListener("DOMContentLoaded", show);
})();
