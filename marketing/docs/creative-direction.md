# Battistics Remote: Companion

Seven iPhone App Store compositions in English and Turkish, combining the three visual directions the owner liked: the night-watch bat, a miniature desk in a pocket, and a closed Mac on a train. The bat direction was the favourite. This revision replaces the rejected typography and copy with Instrument Sans and short, localized feature statements. The owner accepted the complete screenshot series on 2026-11-16 and asked to preserve it. It has not been submitted to App Store Connect. Search/header creative assets remain unfinished; see [asset-status.md](asset-status.md).

Review the exported [English](companion-en.png) and [Turkish](companion-tr.png) contact sheets. Copy lives in [companion.json](../copy/companion.json).

## Visual language

The reference review covered Paylog's subscription passes and statement slips, Recesso's varied physical scenes and native windows, and Elpee's current dark iPhone posters. Battistics uses a tactile bat character, deep petrol, warm ivory, pale mint and restrained citron. Each scene gives the feature a context while real app captures show what the app does.

| Page | English / Turkish headline | Visual evidence |
| --- | --- | --- |
| 1 | Your Mac. Within reach. / Mac’in elinin altında. | Bat watching a closed laptop, actual Live Activity |
| 2 | Your desk. In your pocket. / Masan cebinde. | Miniature desk in a fabric pocket, actual nearby dashboard |
| 3 | Pick a time. Keep it awake. / Süresini seç. Uyanık kalsın. | Actual dashboard and enlarged Keep Awake controls |
| 4 | Lid closed. Still in control. / Kapak kapalı. Kontrol sende. | Train-window photograph and actual Live Activity |
| 5 | Know your Mac’s battery. / Pilini yakından tanı. | Actual battery detail table, gauge and metric crops |
| 6 | Check your accessories, too. / Aksesuarlarının pilini de gör. | Actual accessories and energy-using apps |
| 7 | Close by. Or far away. / Yan yana da. Uzaktayken de. | Actual nearby dashboard and reusable bat pose |

The opening page says Battistics is required on the Mac. The final page explains nearby local-network/Bluetooth routes, private iCloud away, the same-Apple-Account setup requirement and iOS background limits. The copy does not promise uninterrupted delivery. Readings come from sample-mode app captures, not performance or reliability measurements.

The same visual system now includes universal (5244×2950), header (3840×1646) and search (3840×2560 / 1920×1280) assets in English and Turkish. They use a transparent adaptation of the accepted bat/laptop scene, short localized copy and an actual app capture in search. The seed/export scripts preserve the accepted iPhone deck. All eight PNG exports pass text layout, opaque RGB, dimensions and art-safe-bound checks. Six high-resolution creatives are uploaded; dedicated header/search variants are assigned to the 1.1.0 localizations. The universal variants remain reusable alternatives in Asset Library.

## Typography

Instrument Sans is self-hosted from the official [Google Fonts source](https://github.com/google/fonts/tree/main/ofl/instrumentsans), with its SIL Open Font License in `public/fonts/instrument-sans/OFL.txt`. The selected file is `public/fonts/imported/b24f181258481695.ttf` (SHA-256 `b24f1812584816958afcf22e22d08e44318c5e51651e25d2438efdde389b33b1`). Its real 400–700 variable weight range is declared in the editor: 620 for headlines, 420 for supporting copy and 600 for the small wordmark. Leading and tracking are editable and stored per text element. The old condensed face and automatic text shadows are removed.

Headlines use deliberate line breaks, sentence case and left alignment. Turkish and English are composed separately. The export helper measures every text element in the actual export canvas for clipping and unintended wrapping before rendering.

## Sources and reproducibility

`app-store-screenshots.json` remains the editable source in the existing screenshot editor. `scripts/seed-companion.mjs` restores this starting iPhone deck from the copy file; it overwrites later iPhone edits. Other device decks are preserved and are not completed campaigns.

`scripts/build-companion-assets.mjs` builds self-contained SVG viewports containing unmodified captured pixels from `public/screenshots/apple/iphone/{en,tr}`. Native controls, labels and readings are not generated or redrawn. The Turkish crop coordinates follow its actual layout. Phone and overlay paths support `{locale}` in preview and export. Optional Apple bezels remain local; the editor provides a fallback frame.

`public/artwork/companion` contains the selected generated scenes and reusable transparent bat. Exact prompts and generation date are recorded in [artwork-prompts.json](artwork-prompts.json); [mascot.md](mascot.md) records the character direction. These are campaign illustrations, not Apple product photographs or hardware sold with the app.

## Export checks

`scripts/export-campaign.mjs` drives the existing editor exporter in an isolated browser and intercepts autosaves. It writes a ZIP, 56 PNGs (seven pages × two locales × four configured sizes), contact sheets, 160px thumbnail sheets and validation JSON under `.build/app-store-companion`. Checks cover text layout, image/font loading, dimensions, RGB, absence of alpha and source preservation. The exported images are also inspected visually; automated checks do not establish aesthetic approval. Final App Store preview crops remain part of submission.
