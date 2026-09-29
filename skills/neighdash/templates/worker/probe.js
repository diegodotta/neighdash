/**
 * TEMPORARY, never commit. Tags every response the Worker produced, so you can see
 * which paths still invoke it (status codes alone can't show that, traps.md 2 and 3).
 *
 *   cp templates/worker/probe.js worker/_probe.js
 *   npx wrangler dev worker/_probe.js --port 8787
 *   curl -sI http://127.0.0.1:8787/some/path | grep -i x-neighdash-worker
 *   rm worker/_probe.js
 *
 * Header present: the Worker ran (counts against the daily free requests).
 * Header absent: plain static asset (free).
 */
import worker from "./index.js";

export default {
  async fetch(request, env, ctx) {
    const res = await worker.fetch(request, env, ctx);
    const out = new Response(res.body, res);
    out.headers.set("x-neighdash-worker", "1");
    return out;
  },
};
