# Marketing asset status

Checked 2026-11-16. The owner accepted the Companion screenshot series and asked to preserve it. No design choice or approval question is pending.

| Asset | Status | Evidence |
| --- | --- | --- |
| iPhone screenshots, English and Turkish | Complete and accepted | Seven compositions per locale, four configured iPhone sizes: 56 exported opaque RGB PNGs. Text layout and export checks passed. [EN](companion-en.png), [TR](companion-tr.png) |
| Real in-app capture sources | Saved | Curated sample-mode captures in `public/screenshots/apple/iphone/{en,tr}`, native viewport builder in `scripts/build-companion-assets.mjs` |
| Bat, pocket and journey artwork | Saved | Selected originals, transparent bat pose and derived viewports in `public/artwork/companion`; [generation prompts](artwork-prompts.json) |
| Typography and localized copy | Saved | Instrument Sans and OFL licence; `copy/companion.json`; editable `app-store-screenshots.json` |
| App Store universal creative | Not prepared | `creative-universal` still contains the editor's starter text and no app asset |
| App Store product-page header | Not prepared | `creative-header` still contains the editor's starter text and no app asset |
| App Store search creative | Not prepared | `creative-search` still contains the editor's starter text and no app asset |
| App Store Connect upload/submission | Not performed | This is artwork for the upcoming nearby release, not the released binary |

The local screenshot ZIP is `.build/app-store-companion/battistics-remote-companion-en-tr.zip` at repository root. Selected sources and review sheets are committed; local export output can be reproduced with `scripts/export-campaign.mjs`.

The next marketing work is to adapt the accepted visual language into universal/header/search compositions and export/inspect those placements. Their starter decks must not be described as finished assets. Other starter device decks are not completed campaigns either.
