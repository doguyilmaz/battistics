# Battistics Remote on the App Store

## App Store Connect

- Name: Battistics Remote. Bundle ID: `com.doguyilmaz.Battistics.Remote`.
- Category: Utilities. Age rating: 4+.
- Privacy Policy URL: https://www.doguyilmaz.com/legal/privacy/battistics
- Support URL: https://battistics.apps.doguyilmaz.com
- App Privacy: Data Not Collected. The app reads its Mac through the user's
  own private iCloud database; nothing reaches the developer.
- Encryption: exempt (`ITSAppUsesNonExemptEncryption` is false).

## Description, first lines

Battistics Remote needs a Mac running Battistics, signed in to iCloud with
the same Apple Account. Put that first, then the widgets, the Lock Screen
countdown, the Control Center control and the Shortcuts actions.

## Review notes

> Battistics Remote is the companion to Battistics, a free Mac app
> (https://battistics.apps.doguyilmaz.com). It shows a Mac's battery and
> controls Keep Awake through the user's private iCloud database, so it needs
> a Mac signed in to the same Apple Account.
>
> To review it without a Mac, tap **Try a Sample Mac** on the first screen.
> Every control works on made-up readings and nothing is sent anywhere.
> **Show This iPhone's Battery** shows the iPhone's own readings.

## Screenshots

`marketing/` holds the screenshot editor (`bun install`, `bun dev`). The
captures in `marketing/public/screenshots/` stay out of git; take them with
the app's `-demo` launch argument on a 6.9" simulator.

## Before submitting

- A Mac release that can reach the App Store app, shipped first: set the
  `MACOS_PROVISIONING_PROFILE` secret (see RELEASING.md) before tagging it.
  The CloudKit schema is already in Production.
- One end-to-end check with TestFlight against that Mac build.
