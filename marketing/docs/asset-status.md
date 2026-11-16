# Marketing asset status

Checked 2026-11-16. The owner accepted the Companion screenshot series and asked to preserve it. No design choice or approval question is pending.

| Asset | Status | Evidence |
| --- | --- | --- |
| iPhone screenshots, English and Turkish | Complete and accepted | Seven compositions per locale, four configured iPhone sizes: 56 exported opaque RGB PNGs. Text layout and export checks passed. [EN](companion-en.png), [TR](companion-tr.png) |
| Real in-app capture sources | Saved | Curated sample-mode captures in `public/screenshots/apple/iphone/{en,tr}`, native viewport builder in `scripts/build-companion-assets.mjs` |
| Bat, pocket and journey artwork | Saved | Selected originals, transparent bat pose and derived viewports in `public/artwork/companion`; [generation prompts](artwork-prompts.json) |
| Typography and localized copy | Saved | Instrument Sans and OFL licence; `copy/companion.json`; editable `app-store-screenshots.json` |
| App Store universal creative | Complete and uploaded | 5244×2950 EN/TR, reusable alternatives in Asset Library |
| App Store product-page header | Submitted; waiting for review | 3840×1646 EN/TR, assigned to iOS 1.1.0 localizations; both assets WAITING_FOR_REVIEW |
| App Store search creative | Submitted; waiting for review | 3840×2560 and 1920×1280 EN/TR; large versions assigned to iOS 1.1.0 and WAITING_FOR_REVIEW |
| App Store Connect upload/submission | Submitted; waiting for review | iOS 1.1.0 (18), 56 screenshots and four assigned creative assets; submission `ab9231f3-222a-46c3-b84d-eb2aa0d9898c`, 2026-11-16. Six creatives uploaded in total |

The local screenshot ZIP is `.build/app-store-companion/battistics-remote-companion-en-tr.zip` at repository root. Selected sources and review sheets are committed; local export output can be reproduced with `scripts/export-campaign.mjs`.

The complete handoff is `.build/app-store-companion/battistics-complete-assets-1.1.0-en-tr.zip`: all 64 exported PNGs (56 screenshots and eight creative exports), transparent mascot assets, localized copy/metadata, exact artwork prompts, a README and a SHA-256 manifest. All 56 remote screenshot checksums and file sizes match the reviewed local exports.

The creative decks are reproducible with `scripts/seed-creatives.mjs` and `scripts/export-creatives.mjs`. Their text and art fit the measured Apple art-safe areas; estimated crops do not replace Apple's own Preview tool. Other starter device decks are not completed campaigns.

Matching English and Turkish website pages are live at https://battistics.doguyilmaz.com/remote/ and https://battistics.doguyilmaz.com/tr/remote/. These trailing slashes match Astro's canonical routes and the server's 307 redirects from slashless paths. They identify the screenshots and nearby features as a Remote 1.1.0 preview while the public App Store version still uses iCloud. Mac 1.6.0 is live; iOS 1.1.0 remains under review with manual release. See [the release audit](../../docs/releases/1.1.0-review.md).
