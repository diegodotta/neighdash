/**
 * NeighDash legacy-redirect Worker: the old WordPress URLs a static site can't
 * answer with files alone. Copy to worker/index.js and adjust CONFIG.
 *
 *   /?s=kombi                 → 302 /search/?q=kombi          (WordPress search)
 *   /?p=123, /?page_id=45     → 301 to the page                (shortlinks; needs /_wp-ids.json)
 *   /wp-content/uploads/x.jpg, x-1024x683.jpg, x-scaled.jpg
 *                             → 301 /wp-content/uploads/x.webp (only if that file exists)
 *   /tag/x/page/9/ past the end → 301 /tag/x/                  (archive sizes changed)
 *   /<post>/feed/             → 301 /<post>/
 *   /comments/feed/           → 301 /feed/
 *   Yoast sitemaps            → 301 /sitemap.xml
 *   everything else           → the static file, untouched
 *
 * Only the paths in wrangler.jsonc's `run_worker_first` reach this code
 * (templates/wrangler.worker.jsonc). A new redirect here needs a new pattern there,
 * or it silently never runs (traps.md 3). Prove both with scripts/route-check.sh.
 *
 * www to apex belongs in a zone Redirect Rule (templates/www-redirect-rule.json).
 * The check below is only a fallback for the paths that still reach the Worker.
 */

const CONFIG = {
  apex: "example.com",
  searchPath: "/search/",   // null to disable ?s= handling
  wpIdsFile: "/_wp-ids.json", // {"123": "/some-post/"}; null to disable ?p= handling
};

const SITEMAPS = /^\/(sitemap_index|post-sitemap|page-sitemap|category-sitemap|post_tag-sitemap|author-sitemap)\.xml$/;
const UPLOAD = /^(\/wp-content\/uploads\/.+?)(?:-\d+x\d+|-scaled|-rotated)?\.(?:jpe?g|png)$/i;

let idMap = null;
async function wpIds(env, url) {
  if (!idMap) {
    const res = await env.ASSETS.fetch(new URL(CONFIG.wpIdsFile, url));
    idMap = res.ok ? await res.json() : {};
  }
  return idMap;
}

const redirect = (url, to, status = 301) => Response.redirect(new URL(to, url).toString(), status);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.hostname === `www.${CONFIG.apex}`) {
      url.hostname = CONFIG.apex;
      return Response.redirect(url.toString(), 301);
    }

    if (url.pathname === "/") {
      const s = url.searchParams.get("s");
      if (CONFIG.searchPath && s !== null) {
        return redirect(url, `${CONFIG.searchPath}${s ? "?q=" + encodeURIComponent(s) : ""}`, 302);
      }
      const id = url.searchParams.get("p") || url.searchParams.get("page_id");
      if (CONFIG.wpIdsFile && id) {
        const to = (await wpIds(env, url))[id];
        if (to) return redirect(url, to);
      }
    }

    if (SITEMAPS.test(url.pathname)) return redirect(url, "/sitemap.xml");
    if (url.pathname === "/comments/feed/" || url.pathname === "/comments/feed") return redirect(url, "/feed/");

    // The real file always wins. Everything below only runs for URLs with no file.
    const res = await env.ASSETS.fetch(request);
    if (res.status !== 404) return res;

    const up = url.pathname.match(UPLOAD);
    if (up) {
      const webp = `${up[1]}.webp`;
      const probe = await env.ASSETS.fetch(new URL(webp, url), { method: "HEAD" });
      if (probe.ok) return redirect(url, webp);
    }
    const paged = url.pathname.match(/^(.*\/)page\/\d+\/?$/);
    if (paged) return redirect(url, paged[1] || "/");
    const feed = url.pathname.match(/^(\/[^/]+\/)feed\/?$/);
    if (feed) return redirect(url, feed[1]);

    return res;
  },
};
