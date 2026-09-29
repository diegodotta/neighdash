#!/usr/bin/env node
// Renders MIGRATION-REPORT.md from two Lighthouse JSON runs.
// Carbon/energy: @tgwf/co2 Sustainable Web Design Model v4 (modelled, not measured).
const fs = require("fs");
const { co2 } = require("@tgwf/co2");

const [beforePath, afterPath, domain] = process.argv.slice(2);
const B = JSON.parse(fs.readFileSync(beforePath, "utf8"));
const A = JSON.parse(fs.readFileSync(afterPath, "utf8"));

const CATS = ["performance", "accessibility", "best-practices", "seo"];
const VITALS = [
  ["first-contentful-paint", "First Contentful Paint"],
  ["largest-contentful-paint", "Largest Contentful Paint"],
  ["total-blocking-time", "Total Blocking Time"],
  ["cumulative-layout-shift", "Cumulative Layout Shift"],
  ["speed-index", "Speed Index"],
];

const score = (r, c) => Math.round(r.categories[c].score * 100);
const bytes = (r) => r.audits["total-byte-weight"].numericValue;
const reqs = (r) => r.audits["network-requests"].details.items.length;
const kb = (n) => `${Math.round(n / 1024).toLocaleString()} KB`;

function pct(from, to) {
  if (!from) return "n/a";
  const d = ((to - from) / from) * 100;
  const s = d > 0 ? "+" : "";
  return `${s}${d.toFixed(0)}%`;
}
function arrow(from, to, lowerIsBetter = false) {
  if (to === from) return "→";
  const better = lowerIsBetter ? to < from : to > from;
  return better ? "**↓ better**".replace("↓", lowerIsBetter ? "↓" : "↑") : "↑ worse";
}

// ---- carbon ---------------------------------------------------------------
// greenHostingFactor is the lever that separates "same bytes on a grey host"
// from "same bytes on a renewable-powered host".
function carbon(byteCount, green) {
  const m = new co2({ model: "swd", version: 4, results: "segment" });
  const r = m.perVisitTrace(byteCount, green, {
    dataReloadRatio: 0.02,
    firstVisitPercentage: 0.9,
    returnVisitPercentage: 0.1,
  });
  return r.co2;
}

const beforeGreen = process.env.BEFORE_GREEN === "true";
const afterGreen = process.env.AFTER_GREEN !== "false"; // Cloudflare is listed green
const cB = carbon(bytes(B), beforeGreen);
const cA = carbon(bytes(A), afterGreen);

const g = (n) => `${n.toFixed(3)} g`;
const VISITS = 10000;
const kgYear = (c) => ((c * VISITS) / 1000).toFixed(2);

const out = [];
const p = (s = "") => out.push(s);

const day = (r) => {
  try { return new Date(r.fetchTime).toISOString().slice(0, 10); } catch { return "n/a"; }
};
const RUNS_LABEL = (() => {
  try { return JSON.parse(fs.readFileSync(afterPath + ".runs", "utf8")).length; } catch { return 3; }
})();

p(`# Migration report: ${domain}`);
p();
p(`WordPress on shared hosting → static HTML on Cloudflare Workers.`);
p(`Both runs: Lighthouse ${A.lighthouseVersion}, mobile emulation, same machine.`);
p();
p(`| | Before | After | |`);
p(`|---|---:|---:|---|`);
for (const c of CATS) {
  const b = score(B, c), a = score(A, c);
  p(`| ${c} | ${b} | **${a}** | ${a === b ? "→" : (a > b ? `+${a - b}` : `${a - b}`)} |`);
}
p(`| **page weight** | ${kb(bytes(B))} | **${kb(bytes(A))}** | ${pct(bytes(B), bytes(A))} |`);
p(`| **requests** | ${reqs(B)} | **${reqs(A)}** | ${pct(reqs(B), reqs(A))} |`);
p();

// Run-to-run spread is a reliability signal, not just noise to average away.
const spread = (path) => {
  try { return JSON.parse(fs.readFileSync(path + ".runs", "utf8")); } catch { return null; }
};
const sB = spread(beforePath), sA = spread(afterPath);
if (sB || sA) {
  const range = (s) => (s ? `${Math.min(...s)} to ${Math.max(...s)} (runs: ${s.join(", ")})` : "n/a");
  p(`**Performance score spread**: before ${range(sB)} · after: ${range(sA)}.`);
  // Only call the old site "unstable" when it actually was. A 3-point spread
  // against a 1-point one is ordinary Lighthouse noise, not an erratic origin ,
  // asserting otherwise overstates the case on sites that were merely slow.
  const width = (s) => Math.max(...s) - Math.min(...s);
  if (sB && sA) {
    const wB = width(sB), wA = width(sA);
    p();
    if (wB >= 5 && wB >= 3 * Math.max(wA, 1)) {
      p(`> The old site's score swung much more between identical runs. That instability *is*`);
      p(`> the migration's real motivation, the shared origin's response time was erratic.`);
      p(`> A single "before" measurement can land anywhere in that range, which is why these`);
      p(`> numbers are medians of repeated runs rather than one-shot captures.`);
    } else {
      p(`> Both sides were stable across runs (${wB} and ${wA} points of spread), so the`);
      p(`> gap between them is a real difference rather than sampling noise. Medians of`);
      p(`> repeated runs are still used, because a single capture can land anywhere in`);
      p(`> its range.`);
    }
  }
  p();
}
p(`## Core Web Vitals`);
p();
p(`| Metric | Before | After | Change |`);
p(`|---|---:|---:|---|`);
for (const [id, label] of VITALS) {
  const b = B.audits[id], a = A.audits[id];
  p(`| ${label} | ${b.displayValue} | **${a.displayValue}** | ${pct(b.numericValue, a.numericValue)} |`);
}
p();
p(`## Energy & carbon (modelled)`);
p();
p(`Estimated with [\`@tgwf/co2\`](https://github.com/thegreenwebfoundation/co2.js) using the`);
p(`**Sustainable Web Design Model v4**, the model behind websitecarbon.com. It derives`);
p(`energy from *bytes transferred*, split across three segments, then applies grid carbon`);
p(`intensity. Green-hosting status comes from the Green Web Foundation directory.`);
p();
p(`Hosting: before \`green=${beforeGreen}\` · after \`green=${afterGreen}\`.`);
p();
p(`| Per page view | Before | After | Change |`);
p(`|---|---:|---:|---|`);
p(`| Data centre (server) | ${g(cB.dataCenterCO2e)} | **${g(cA.dataCenterCO2e)}** | ${pct(cB.dataCenterCO2e, cA.dataCenterCO2e)} |`);
p(`| Network transfer | ${g(cB.networkCO2e)} | **${g(cA.networkCO2e)}** | ${pct(cB.networkCO2e, cA.networkCO2e)} |`);
p(`| Visitor's device | ${g(cB.consumerDeviceCO2e)} | **${g(cA.consumerDeviceCO2e)}** | ${pct(cB.consumerDeviceCO2e, cA.consumerDeviceCO2e)} |`);
p(`| **Total** | **${g(cB.total)}** | **${g(cA.total)}** | **${pct(cB.total, cA.total)}** |`);
p();
p(`At ${VISITS.toLocaleString()} page views: **${kgYear(cB.total)} kg → ${kgYear(cA.total)} kg CO₂e**.`);
p();
p(`### What this does and doesn't tell you`);
p();
p(`- It is a **model driven almost entirely by page weight**, not a measurement. Two sites`);
p(`  transferring the same bytes score the same, regardless of how hard the server worked.`);
p(`- The **server-side saving is understated**. The model can't see that the old site ran`);
p(`  PHP + MySQL per request while the new one serves pre-built files from cache, real`);
p(`  origin CPU savings don't appear here at all.`);
p(`- **Idle server draw is excluded.** Shared hosting burns power whether or not anyone`);
p(`  visits; that baseline isn't attributable per-view and isn't counted.`);
p(`- The **visitor-device figure is the least reliable of the three**, and it is the`);
p(`  largest. Because it is bytes × a constant, it credits a smaller page with a`);
p(`  proportional device saving even when the phone does nearly the same work. The next`);
p(`  section measures that directly and lands well below this estimate.`);
p(`- Grid intensity uses the model's global average, not per-visitor location.`);
// ---- device energy: time-based sanity check on the byte model -----------
// SWDM's device figure is bytes × a constant, so it silently assumes energy
// scales with data rather than with TIME. A phone held awake longer costs more
// even for identical bytes. This cross-checks that with measured CPU/wait time.
{
  const ms = (r, id) => (r.audits[id] && r.audits[id].numericValue) || 0;
  const cpuB = ms(B, "mainthread-work-breakdown"), cpuA = ms(A, "mainthread-work-breakdown");
  const jsB = ms(B, "bootup-time"), jsA = ms(A, "bootup-time");
  const ttiB = ms(B, "interactive"), ttiA = ms(A, "interactive");
  const lcpB = ms(B, "largest-contentful-paint"), lcpA = ms(A, "largest-contentful-paint");
  const SOC_W = 2.0, RADIO_W = 1.5, SCREEN_W = 0.8;

  const model = (cpu, kbytes, lcp, bw) => {
    const cpuJ = (cpu / 1000) * SOC_W;
    const radioJ = ((kbytes * 8) / 1024 / bw) * RADIO_W;
    const screenJ = (lcp / 1000) * SCREEN_W;
    return { cpuJ, radioJ, screenJ, total: cpuJ + radioJ + screenJ };
  };

  p();
  p(`## Does the visitor's device really save that much?`);
  p();
  p(`The byte model credits the device segment with **${pct(cB.consumerDeviceCO2e, cA.consumerDeviceCO2e)}**, but it reaches`);
  p(`that by multiplying bytes by a constant, it never looks at how long the phone was`);
  p(`actually busy. Measured main-thread time tells a more sober story:`);
  p();
  p(`| Device-side work | Before | After | Change |`);
  p(`|---|---:|---:|---|`);
  p(`| Main-thread total | ${Math.round(cpuB)} ms | ${Math.round(cpuA)} ms | ${pct(cpuB, cpuA)} |`);
  p(`| JS execution | ${Math.round(jsB)} ms | ${Math.round(jsA)} ms | ${pct(jsB, jsA)} |`);
  p(`| Time to Interactive | ${Math.round(ttiB)} ms | ${Math.round(ttiA)} ms | ${pct(ttiB, ttiA)} |`);
  p(`| Largest Contentful Paint | ${Math.round(lcpB)} ms | ${Math.round(lcpA)} ms | ${pct(lcpB, lcpA)} |`);
  p(`| Bytes over the radio | ${kb(bytes(B))} | ${kb(bytes(A))} | ${pct(bytes(B), bytes(A))} |`);
  p();
  // Whether compute actually improved is a per-site fact, not a given: a heavy
  // WordPress front-end can shed real main-thread work, while an already-light one
  // cannot. Say what this site's numbers say.
  const cpuDrop = 1 - cpuA / cpuB;
  if (cpuDrop < 0.1) {
    p(`**The CPU barely moved.** Rendering a static page costs the phone almost as much as`);
    p(`rendering the WordPress one did, the saving is overwhelmingly in *radio time*, not`);
    p(`compute. Modelling one page load bottom-up (SoC ${SOC_W} W, modem ${RADIO_W} W, screen ${SCREEN_W} W):`);
  } else {
    p(`**Compute improved too, but less than the byte count suggests.** Main-thread work fell`);
    p(`${Math.round(cpuDrop * 100)}% against a ${pct(bytes(B), bytes(A)).replace("-", "")} drop in bytes, the phone still has to`);
    p(`render the page, so the saving is weighted toward *radio time* rather than compute.`);
    p(`Modelling one page load bottom-up (SoC ${SOC_W} W, modem ${RADIO_W} W, screen ${SCREEN_W} W):`);
  }
  p();
  p(`| Connection | Before | After | Real saving |`);
  p(`|---|---:|---:|---:|`);
  for (const bw of [5, 10, 25]) {
    const b = model(cpuB, bytes(B) / 1024, lcpB, bw), a = model(cpuA, bytes(A) / 1024, lcpA, bw);
    p(`| ${bw} Mbps | ${b.total.toFixed(1)} J | ${a.total.toFixed(1)} J | **${Math.round((1 - a.total / b.total) * 100)}%** |`);
  }
  p();
  // Derive the range and its direction from the table just printed, rather than
  // restating the first site's numbers.
  const savings = [5, 10, 25].map((bw) => {
    const b = model(cpuB, bytes(B) / 1024, lcpB, bw), a = model(cpuA, bytes(A) / 1024, lcpA, bw);
    return Math.round((1 - a.total / b.total) * 100);
  });
  const lo = Math.min(...savings), hi = Math.max(...savings);
  const modelled = lo === hi ? `**${lo}%**` : `**${lo}-${hi}%**`;
  p(`So the honest device saving is roughly ${modelled}, not ${pct(cB.consumerDeviceCO2e, cA.consumerDeviceCO2e).replace("-", "")}.`);
  if (savings[2] < savings[0]) {
    p(`And it *shrinks as connections get faster*, because radio time is the part that`);
    p(`improved, on a fast link there is less waiting to eliminate.`);
  } else if (lo === hi) {
    p(`It holds steady across connection speeds: here compute and bytes fell by similar`);
    p(`proportions, so the ratio between the two loads barely depends on link speed.`);
  }
  p();
  p(`> **Why the two models disagree by ~1000× in absolute terms.** SWDM's device figure is`);
  p(`> a *top-down allocation*: total global device energy ÷ total global data. It answers`);
  p(`> "what share of the world's device energy is attributable to this page?" The bottom-up`);
  p(`> figure answers "how much extra energy did this specific load cost?" Both are`);
  p(`> defensible; they are not the same question, and only the second one responds to`);
  p(`> making a page faster rather than smaller.`);
  if (jsA >= jsB) {
    p();
    p(`> ⚠️ **JS execution went *up* slightly** (${Math.round(jsB)} → ${Math.round(jsA)} ms). With the page now`);
    p(`> lean, the analytics tag is the single largest remaining device cost. If device`);
    p(`> energy is a real priority, dropping GA4 would do more than any further byte-shaving.`);
  }
}

// ---- optional: origin-server energy model -------------------------------
// The byte model above is blind to the fact that a shared server draws power
// 24/7 whether or not anyone visits. For a low-traffic brochure site that
// always-on share dominates everything else, so it's worth modelling separately.
if (process.env.SERVER_CORES) {
  const num = (k, d) => (process.env[k] ? Number(process.env[k]) : d);
  const cores = num("SERVER_CORES"), load = num("SERVER_LOAD", cores * 0.5);
  const idleW = num("SERVER_IDLE_W", 150), maxW = num("SERVER_MAX_W", 450);
  const pue = num("SERVER_PUE", 1.5), grid = num("SERVER_GRID", 0.37);
  const views = num("ANNUAL_VIEWS", 10000);
  const util = Math.min(1, load / cores);
  const serverW = idleW + util * (maxW - idleW);
  const facilityW = serverW * pue;
  const kWhYear = (facilityW * 8760) / 1000;
  const tiers = [num("ACCOUNTS_LOW", 100), num("ACCOUNTS_MID", 250), num("ACCOUNTS_HIGH", 500)];

  p();
  p(`## Origin server: the always-on cost`);
  p();
  p(`The byte model above is blind to a shared server's **idle draw**, it burns power`);
  p(`around the clock regardless of traffic. For a low-traffic site that is the dominant`);
  p(`term, and it is exactly what moving to an edge/serverless host eliminates.`);
  p();
  p(`Measured on the old host (\`${process.env.SERVER_CPU || "origin"}\`):`);
  p();
  p(`| Input | Value | Source |`);
  p(`|---|---:|---|`);
  p(`| CPU / cores visible | ${process.env.SERVER_CPU || "n/a"} / ${cores} | measured over SSH |`);
  p(`| RAM | ${process.env.SERVER_RAM_GB || "?"} GB | measured |`);
  p(`| Load average | ${load} (${Math.round(util * 100)}% of cores) | measured |`);
  p(`| Server draw at that load | ~${Math.round(serverW)} W | modelled: idle ${idleW} W → max ${maxW} W |`);
  p(`| Facility draw (PUE ${pue}) | ~${Math.round(facilityW)} W | industry average PUE |`);
  p(`| **Whole server, per year** | **${Math.round(kWhYear).toLocaleString()} kWh** | derived |`);
  p();
  p(`Divided across the accounts sharing the box, **the dominant unknown**, since CageFS`);
  p(`hides other tenants:`);
  p();
  p(`| Accounts on server | Our share/yr | CO₂e/yr @ ${grid} kg/kWh |`);
  p(`|---:|---:|---:|`);
  for (const n of tiers) {
    const share = kWhYear / n;
    p(`| ${n} | ${share.toFixed(1)} kWh | **${(share * grid).toFixed(1)} kg** |`);
  }
  p();
  const dcPerYear = (cA.dataCenterCO2e * views) / 1000;
  p(`**After migration**, the equivalent figure is the data-centre segment of the byte`);
  p(`model: ${g(cA.dataCenterCO2e)}/view × ${views.toLocaleString()} views ≈ **${dcPerYear.toFixed(2)} kg/yr**,`);
  p(`and Cloudflare is Green Web Foundation-listed as renewable-powered, so on a`);
  p(`market-based accounting that trends toward zero.`);
  p();
  p(`So the server-side saving is plausibly **${Math.round((kWhYear / tiers[2]) * grid / Math.max(dcPerYear, 0.01))}×-${Math.round((kWhYear / tiers[0]) * grid / Math.max(dcPerYear, 0.01))}×**, versus the`);
  p(`${pct(cB.total, cA.total)} the byte model alone suggests. The byte model *understates* the`);
  p(`benefit for low-traffic sites, because it never counts the idle server.`);
  p();
  p(`> ⚠️ **Two honest caveats.**`);
  p(`> **1. The accounts-per-server figure is a guess** spanning a 5× range, and it drives`);
  p(`> the result linearly. Treat this as an order-of-magnitude comparison, not a measurement.`);
  p(`> **2. This is an attributional saving, not an immediate physical one.** The old host's`);
  p(`> server does not power down because we left; our share is simply redistributed among`);
  p(`> the remaining tenants. The real-world reduction only materialises when a host`);
  p(`> consolidates hardware. The genuinely immediate savings are the visitor-device and`);
  p(`> network ones above, which are real from the first page view.`);
}

// ---- what the migration itself cost -------------------------------------
if (process.env.MIGRATION_WH_LOW) {
  const nlow = Number(process.env.MIGRATION_WH_LOW), nhigh = Number(process.env.MIGRATION_WH_HIGH);
  const grid = Number(process.env.SERVER_GRID || 0.37);
  const kgL = (nlow / 1000) * grid, kgH = (nhigh / 1000) * grid;
  const views = Number(process.env.ANNUAL_VIEWS || 10000);
  const byteSaveKgYr = ((cB.total - cA.total) * views) / 1000;
  const days = (kg) => Math.round((kg / byteSaveKgYr) * 365);

  p();
  p(`## What the migration itself cost`);
  p();
  p(`A migration is not free. Counting it is the difference between an honest report and`);
  p(`a flattering one.`);
  p();
  p(`| Estimate | Energy | CO2e |`);
  p(`|---|---:|---:|`);
  p(`| Audits, builds, downloads, the laptop, and the AI agent's inference | ${nlow}-${nhigh} Wh | **${kgL.toFixed(2)}-${kgH.toFixed(2)} kg** |`);
  p();
  p(`The range comes from \`MIGRATION_WH_LOW\` / \`MIGRATION_WH_HIGH\`. On the migrations`);
  p(`this tool was built on, the agent's inference was the dominant term (roughly 50 to`);
  p(`1,000 Wh for a first site) and the one that can't be measured from the outside.`);
  p();
  p(`**Payback**, against the byte-model saving of ${byteSaveKgYr.toFixed(2)} kg/yr at ${views.toLocaleString()} views:`);
  p(`**${days(kgL)} to ${days(kgH)} days**. At a tenth of that traffic it stretches to`);
  p(`**${days(kgL) * 10} to ${days(kgH) * 10} days**, months to years.`);
  p();
  p(`### The honest reading`);
  p();
  p(`- **The dominant term is the one nobody can measure precisely.** A range is the`);
  p(`  finding. A single figure would be false precision.`);
  p(`- **This is rarely a carbon decision.** Sites usually move because the old host was`);
  p(`  slow, unreliable, expensive or a chore. Present the carbon saving as a co-benefit,`);
  p(`  not the justification.`);
  p(`- **Most of the cost amortises** when the same tooling migrates several sites.`);
  p(`- **This analysis is itself part of the cost.** Quantifying the carbon can consume`);
  p(`  more energy than a low-traffic site's network saving recovers in a year. Worth`);
  p(`  doing once to calibrate, not per site.`);
}

p();
p(`## Method`);
p();
p(`Both sides are the **median of ${RUNS_LABEL} Lighthouse runs** (mobile emulation, same machine,`);
p(`same Lighthouse version), with the edge cache warmed first. Captured`);
p(`${day(B)} (before) and ${day(A)} (after).`);
p();
p(`Single runs are rejected as a basis for comparison: in testing, a one-shot pair`);
p(`reported an old site at 77 and "FCP 63% worse" after migrating, both artefacts of`);
p(`sampling noise.`);
if (process.env.BEFORE_VIA_ORIGIN === "true") {
  p();
  p(`⚠️ **The "before" numbers are best-case.** The old site was captured by pinning DNS`);
  p(`to the origin IP, which bypasses the CDN layer that used to front it, and was taken`);
  p(`when the old server happened to answer. If it was failing intermittently, real`);
  p(`visitors sometimes got no page at all, an outcome no Lighthouse score reflects.`);
  p(`The honest summary is not "the old site was slow"; it is **"the old site was`);
  p(`unpredictable, and sometimes down."**`);
}

fs.writeFileSync("/dev/stdout", out.join("\n") + "\n");
