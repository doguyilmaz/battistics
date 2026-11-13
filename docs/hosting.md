# Website and email

The product website is https://battistics.doguyilmaz.com. Cloudflare Worker
`battistics-site` serves the Astro site from `site/dist`.

## Deploy the website

From `site`, using the existing personal Cloudflare account:

Use Bun `1.4.4`, pinned in `site/package.json`. The Cloudflare Workers Builds
trigger also sets `BUN_VERSION=1.4.4` so dependency installation uses the same
version. Update both pins together. The old build image's Bun `1.2.15` cannot
read this repository's version-2 `bun.lock` format and fails before the build.

```sh
rtk bun install --frozen-lockfile
rtk bun run build
rtk bunx wrangler deploy --dry-run
rtk bunx wrangler deploy --keep-vars
```

`site/wrangler.jsonc` binds both the current domain and
`battistics.apps.doguyilmaz.com`. Keep the legacy binding: installed apps still
use it, and HTTPS redirects need its DNS record and certificate.

The site uses canonical trailing slashes for documentation pages, such as
https://battistics.doguyilmaz.com/docs/privacy/. Cloudflare redirects the
slashless page paths to that form. Root links use the slashless hostname.

## Redirect rules

The zone's `http_request_dynamic_redirect` ruleset contains the two product
rules declared in [redirects.json](../site/cloudflare/redirects.json):

- `battistics_canonical_domain`: all HTTP/HTTPS requests to the legacy host
  receive a permanent `301` redirect to the new host, preserving the path and
  query string.
- `battistics_privacy_policy`: the old `/legal/privacy/battistics` policy on
  `doguyilmaz.com` and `www.doguyilmaz.com` redirects to the full policy at
  `/docs/privacy/`. Both forms of the old path, with and without a slash, work.

These are zone rules managed with `cf`, separate from Worker deployments.
Inspect the current entrypoint before changing them:

```sh
rtk cf rulesets entrypoint get http_request_dynamic_redirect --zone doguyilmaz.com
```

Match existing rules by `ref`. To update one, use
`rtk cf rulesets rules update <rule-id> --ruleset-id <ruleset-id> --zone doguyilmaz.com`
with its JSON object as `--body`, first with `--dry-run`. Create a rule only if
its `ref` is missing. Preserve all unrelated rules in the zone; do not replace
the whole entrypoint with this two-rule manifest.

Cloudflare's [custom domain documentation](https://developers.cloudflare.com/workers/configuration/routing/custom-domains/)
describes automatic DNS and certificate management. The redirect follows its
[domain migration example](https://developers.cloudflare.com/rules/url-forwarding/examples/redirect-all-another-domain/).

## Support email

`battistics@doguyilmaz.com` is an enabled Cloudflare Email Routing address,
forwarding to the owner's existing verified personal Gmail destination. It was
already configured at migration time; no duplicate rule or new mailbox is
needed. The zone is enabled, synced and ready, with Cloudflare MX, SPF and DKIM
records configured.

```sh
rtk cf email-routing settings get --zone doguyilmaz.com
rtk cf email-routing rules list-account --zone doguyilmaz.com
rtk cf email-routing addresses list
rtk cf email-routing dns get --zone doguyilmaz.com
```

Routing forwards incoming mail; it does not configure sending as this address.
The website, privacy policy and macOS problem reporter use this support alias.

## App and store links

README links, macOS Website/Help/automation guides, and iOS Website/Help,
privacy and Mac setup links use the new host. Those source changes ship with
the next binaries; the redirects also support versions already installed.

App Store Connect's English and Turkish marketing, support and privacy URLs
are synced from `metadata` for iOS `1.0.1`. App Review notes use the new website
and the review contact uses the support alias. GitHub's repository homepage and
the Homebrew cask homepage also use the new host. The cask generator lives in
`scripts/update-tap.sh`.

After a deployment, verify HTTPS, the sitemap/canonical URLs, documentation,
download and contact links, plus redirects with a nested path and query string.
