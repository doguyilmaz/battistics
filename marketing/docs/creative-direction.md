# Battistics Remote: Still On

Six iPhone App Store compositions in English and Turkish. This replaces the rejected Field Notes draft. It is a design for the upcoming coordinated nearby release and has not been submitted to App Store Connect. It is a review draft, not recorded owner approval.

Review the exported [English](still-on-en.png) and [Turkish](still-on-tr.png) contact sheets.

## Reference review

The actual local artwork was inspected:

- Paylog: `budget-manager/docs/diagnostics/store-marketing/contact-sheet.png` — subscription passes, statement slips and budget bars carry each idea without a full phone.
- Recesso: `recesso/store/screenshots/en-US/01-three-rhythms.png`, `03-water.png` and `06-menu-bar.png` — one meaningful scene per page, native windows, varied scale and physical metaphors.
- Elpee: `elpee/release/screenshots/selected/posters/iphone/en/01-hero.png` — a consistent dark identity, large typography and actual content. Its older light contact sheet was examined but is not the current reference.

Battistics uses its own material: orange Keep Awake controls, an actual countdown, Live Activity, battery instrumentation and routes between Mac and iPhone. Charcoal, warm silver/paper and signal orange support compact industrial typography. The six-page rhythm is still life + session, timer + Live Activity, one full phone, enlarged battery details, accessories + app readings, and a connection diagram. Every page stands alone.

## Copy

| Page | Selected English / Turkish | Other directions considered |
| --- | --- | --- |
| 1 | Your Mac. Still on. / Sen uzakta. Mac uyanık. | Leave the desk. Let it finish. / Keep your Mac awake from iPhone. |
| 2 | One tap. More time. / Dokun. Süre ekle. | Thirty more minutes. / Your session, within reach. |
| 3 | Your hours. Your rules. / Süre senin. Mod senin. | Keep it running your way. / Screen on, off, or lid closed. |
| 4 | Behind the percentage. / Yüzdenin ötesini gör. | Know your Mac’s charge. / Read the whole battery story. |
| 5 | All your batteries. / Tüm piller. Tek bakış. | Your desk, at a glance. / See what’s using energy. |
| 6 | Near. Far. Yours. / Yakında. Uzakta. Senin. | Your devices, your connection. / Nearby Bluetooth, private iCloud away. |

Copy describes available routes without promising uninterrupted background delivery. The last page states the same-Apple-Account requirement and iOS background constraint. Synthetic status numbers are demo readings, not adoption, performance or reliability claims.

## Sources and reproducibility

`../app-store-screenshots.json` is the editable source in the existing screenshot editor. `scripts/seed-campaign.mjs` restores this starting iPhone deck; save later editor changes before rerunning it. Other device decks are preserved and are not completed campaigns.

`scripts/build-campaign-assets.mjs` creates original vector decoration and SVG viewports containing the unmodified real EN/TR captures in `public/screenshots/apple/iphone`. These enlarge actual interface details; crop coordinates differ where Turkish layout differs. No app control is generated or redrawn. Overlay image paths support `{locale}` for both preview and export.

Barlow Condensed ExtraBold comes from [Google Fonts](https://github.com/google/fonts/tree/main/ofl/barlowcondensed). Its SIL Open Font License is `public/fonts/barlow-condensed/OFL.txt`; the selected font is `public/fonts/imported/724c9c25952d5f4a.ttf`. No proprietary system font is redistributed. Optional Apple bezels remain local; the editor has a fallback frame.

The built-in image generation tool produced `public/artwork/on-duty/power-key.png` on 2026-11-16. It is an original editorial still life, not an Apple product photograph or hardware sold with the app. The project contains the selected file. The rejected ribbon/laptop illustration is unused.

Prompt: ads-marketing, transparent cutout for Battistics Remote, an iPhone companion controlling Mac Keep Awake sessions. A thin closed unbranded aluminum laptop, lid fully shut, floating diagonally behind an oversized burnt-orange mechanical keyboard key bearing a recessed simple power symbol. The key is a sculptural metaphor. Restrained industrial design; warm silver anodized metal, matte orange #FF7A32 keycap, dark charcoal sides, fine illuminated edge, realistic microtexture. Laptop dominant, clear three-quarter top view, dark hinge and tiny warm status light. All objects contained; strong directional studio lighting and convincing shadow; compact landscape silhouette and transparent surroundings. No ribbons, infinity shapes, rings, glossy blobs, scenery, cables, coffee, people, logos, letters, numbers, watermark, phone screens or generated UI. Only marking: a standard simple power glyph.

## Export checks

`scripts/export-campaign.mjs` drives the existing editor exporter in an isolated browser and intercepts autosaves. It writes a ZIP, 48 PNGs (six pages × two locales × four configured sizes), contact sheets, 160px thumbnail sheets and validation JSON under `.build/app-store-still-on`. Checks cover image/font loading, dimensions, RGB, absence of alpha and source preservation. The actual PNGs are visually inspected. Automated checks do not establish aesthetic approval; final App Store preview crops remain part of submission.

Export diagnostics use full overlay bounds and a 32px high-quality fingerprint so sparse vector artwork is checked without disappearing between probe samples. This retains the missing-image warning rather than suppressing it.
