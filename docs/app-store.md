# Battistics Remote on the App Store

## App Store Connect

- Name: Battistics Remote. Bundle ID: `com.doguyilmaz.Battistics.Remote`.
- Category: Utilities. Age rating: 4+.
- Privacy Policy URL: https://battistics.doguyilmaz.com/docs/privacy/
- Support URL: https://battistics.doguyilmaz.com
- Contact email: battistics@doguyilmaz.com
- Listing: https://apps.apple.com/app/id6827062128
- App Privacy: Data Not Collected. The app reads its Mac through the user's
  own private iCloud database and authenticated nearby connections; nothing reaches the developer. Nearby permissions do not introduce developer-side data collection.
- Encryption: exempt (`ITSAppUsesNonExemptEncryption` is false).

## Description, first lines

Battistics Remote needs a Mac running Battistics, signed in to iCloud with
the same Apple Account. Put that first, then the widgets, the Lock Screen
countdown, the Control Center control and the Shortcuts actions.

## Review notes

> Battistics Remote is the companion to Battistics, a free Mac app
> (https://battistics.doguyilmaz.com). It shows a Mac's battery and
> controls Keep Awake through the user's private iCloud database, so it needs
> a Mac signed in to the same Apple Account.
> Updated versions of both apps also use encrypted nearby Bluetooth and local-network connections. Allow both permissions when prompted; they can be changed later in Settings. iCloud continues without a nearby connection.
>
> To review it without a Mac, tap **Try a Sample Mac** on the first screen.
> Every control works on made-up readings and nothing is sent anywhere.
> **Show This iPhone's Battery** shows the iPhone's own readings.

## Screenshots

`marketing/` holds the screenshot editor (`bun install`, `bun dev`). The
curated sample-mode iPhone captures referenced by the Companion deck are tracked; other captures/uploads and Apple bezels remain local. Capture fresh app states with `-demo`. The editor exports the seven-slide EN/TR series at all four configured iPhone sizes, combining actual UI with the bat, pocket and journey campaign scenes. Copy, typography, character references and artwork prompts are recorded in [the creative brief](../marketing/docs/creative-direction.md). Do not present this upcoming nearby release's screenshots as the older App Store binary.

Released metadata in `metadata/version/1.0.1/` records what shipped. Upcoming nearby copy is staged separately under `metadata/drafts/nearby/`; select the actual next SemVer and complete release validation before moving it into version metadata or submitting it. Do not publish an unreleased feature as available in the current App Store binary.

## Before submitting

- A Mac release that can reach the App Store app, shipped first: set the
  `MACOS_PROVISIONING_PROFILE` secret (see RELEASING.md) before tagging it.
  The CloudKit schema is already in Production.
- One end-to-end check with TestFlight against that Mac build.
