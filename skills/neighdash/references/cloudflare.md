# Cloudflare recipes

API calls for the steps a script can't do safely on its own. Run them through the
Cloudflare MCP server (`execute`, which exposes `cloudflare.request()` and
`accountId`) or with `curl` and a scoped API token. The wrangler OAuth login is not
enough for zone work (traps.md 25). Every write here is outward facing: show the
user what will change and get a yes first.

## Free plan limits that shape the design (checked September 2026)

| Limit | Free plan | Why it matters |
|---|---|---|
| Worker requests | 100,000 a day **per account**, reset at midnight UTC, then Error 1027 | Shared by every site. Keep `run_worker_first` narrow. |
| Static asset requests | Free and unlimited | The reason NeighDash serves files, not code. |
| Files per Worker version | 20,000 | A big blog with many image sizes can hit it. |
| Size per file | 25 MiB | Re-encode long videos, or move them to R2. |
| `_headers` | 100 rules | |
| `_redirects` | 2,000 static + 100 dynamic | Beyond that, Bulk Redirects. |
| Single Redirect rules | 10 per zone | The www rule needs one slot. |
| Workers Builds | 3,000 build minutes a month, 1 at a time, 20 min timeout | Pushing to production is a build. Batch changes. |

Re-check the current numbers in the docs before quoting them to the user.

## Create a git-connected Worker with only a production trigger

The dashboard's "Import a repository" works, but also creates a "Deploy
non-production branches" trigger (traps.md 5). Either delete that trigger:

```
GET    /accounts/{account_id}/builds/workers/{script_tag}/triggers
DELETE /accounts/{account_id}/builds/triggers/{trigger_uuid}
```

or create everything through the API:

```
PUT  /accounts/{account_id}/workers/scripts/{name}     # placeholder module Worker, gives you the script tag
PUT  /accounts/{account_id}/builds/repos/connections   # links the GitHub repo
POST /accounts/{account_id}/builds/triggers            # branch_includes: ["main"], branch_excludes: []
```

`POST /builds/triggers` needs a `build_token_uuid`, which comes from a user-scoped API
token. The first push to the production branch replaces the placeholder. The build
config keys off the script tag, not the name. To check that Cloudflare's GitHub app
can see a new repo before committing to anything:
`GET /accounts/{account_id}/builds/repos/github/{owner_id}/{repo_id}/config_autofill?branch=main`.

## Cutover: records out, domains in, automatic rollback

Run as one call. Adjust the names. This is the version that took 1.3 seconds from
first delete to both domains attached.

```js
async () => {
  const apex = "example.com", worker = "example-com";
  const z = (await cloudflare.request({ method: "GET", path: "/zones", query: { name: apex } })).result[0];
  const hosts = [apex, `www.${apex}`];
  // 1. back up exactly the web records (never MX, TXT, mail hosts)
  const backup = [];
  for (const h of hosts) {
    const r = await cloudflare.request({ method: "GET", path: `/zones/${z.id}/dns_records`, query: { name: h } });
    backup.push(...r.result.filter(x => ["A", "AAAA", "CNAME"].includes(x.type)));
  }
  // 2. delete them
  for (const rec of backup) await cloudflare.request({ method: "DELETE", path: `/zones/${z.id}/dns_records/${rec.id}` });
  // 3. attach both domains, restore everything if either fails
  try {
    for (const hostname of hosts) {
      const a = await cloudflare.request({ method: "PUT", path: `/accounts/${accountId}/workers/domains`,
        body: { hostname, service: worker, zone_id: z.id } });
      if (!a.success) throw new Error(JSON.stringify(a.errors));
    }
  } catch (e) {
    for (const rec of backup) await cloudflare.request({ method: "POST", path: `/zones/${z.id}/dns_records`,
      body: { type: rec.type, name: rec.name, content: rec.content, proxied: rec.proxied, ttl: rec.ttl } });
    return { rolledBack: true, error: String(e), restored: backup.length };
  }
  return { ok: true, backup };  // save this output in the handoff folder
}
```

Afterwards, declare the domains in `wrangler.jsonc` (`routes` with
`custom_domain: true`) and push. The build finds them already attached and succeeds.

## www to apex as a Redirect Rule

Needs one of the zone's 10 Single Redirect slots. If the zone has no dynamic
redirect ruleset yet, create it:

```
POST /zones/{zone_id}/rulesets
{ "name": "default", "kind": "zone", "phase": "http_request_dynamic_redirect",
  "rules": [ <templates/www-redirect-rule.json> ] }
```

If it exists (`GET /zones/{zone_id}/rulesets/phases/http_request_dynamic_redirect/entrypoint`
answers), add one rule without touching the others:

```
POST /zones/{zone_id}/rulesets/{ruleset_id}/rules   <templates/www-redirect-rule.json>
```

Test: `curl -sI https://www.example.com/some/page/?x=1` answers 301 to
`https://example.com/some/page/?x=1`. The rule lives in Cloudflare, not git.
Record its ruleset id in the handoff doc, and keep a www check in the route list.

## Bot Fight Mode (both halves)

```
GET /zones/{zone_id}/bot_management
PUT /zones/{zone_id}/bot_management   {"fight_mode": false, "enable_js": false}
```

Send only those two fields. The GET returns read-only fields that make a full-body
PUT fail with `10400`. For a static site with no forms or logins it buys almost
nothing and costs about a second of main-thread time (traps.md 8).

## Purge after a content deploy

```
POST /zones/{zone_id}/purge_cache   {"purge_everything": true}
```

Then probe several times and log status plus byte size (traps.md 9).

## How much of the Worker budget is used

```js
async () => {
  const q = `query($a:String!,$s:Date!,$e:Date!){viewer{accounts(filter:{accountTag:$a}){
    workersInvocationsAdaptive(limit:500,filter:{date_geq:$s,date_leq:$e},orderBy:[date_ASC]){
      sum{requests errors} dimensions{date scriptName}}}}}`;
  const r = await cloudflare.request({ method: "POST", path: "/graphql",
    body: { query: q, variables: { a: accountId, s: "2026-09-21", e: "2026-09-28" } } });
  return r.result.viewer.accounts[0].workersInvocationsAdaptive;
}
```

Sum per day across scripts and compare with 100,000.

## Other zone settings worth a look

`GET /zones/{zone_id}/settings/brotli` (on), `early_hints` (on), `rocket_loader`
(off: it defers scripts and tends to hurt a static site more than it helps).
