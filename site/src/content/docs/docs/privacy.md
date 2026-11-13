---
title: Privacy Policy
description: What Battistics and Battistics Remote read, store and send.
---

**Last Updated: November 13, 2026**

## Overview

Battistics is a menu bar app for the Mac that shows battery health, power and history and keeps the Mac awake when needed. Battistics Remote is its iPhone companion. This policy covers both apps.

## The Short Version

- Battistics has no accounts, no analytics, no ads and no tracking.
- Nothing is sent to us. We run no server and cannot see your data.
- Battery history stays on your Mac. What Battistics Remote reads about your iPhone stays on your iPhone.
- If you share a Mac with your iPhone, the two talk through your own private iCloud database, which only your Apple Account can read.

## Information We Collect

**None.** We do not collect, receive or store any information about you or your devices.

## Data That Stays on Your Mac

Battistics reads what macOS reports about the battery and power (charge, health, cycles, temperature, power draw, the adapter) and stores a history of these readings on your Mac. It can also show the battery level of connected Bluetooth accessories and which apps use the most energy, measured only while you look.

- This data never leaves your Mac unless you turn on sharing with your iPhone, described below.
- You can export or delete the history at any time in Battistics › Data.
- The optional help assistant uses Apple’s on-device model on macOS 26. Your questions are not sent anywhere and are not saved.
- Terminal and AI client automation uses a local connection on your Mac only. No port is opened to the network.

## Sharing a Mac with Your iPhone

Sharing is off by default. When you turn on **Show this Mac in Battistics Remote**:

- The Mac writes its current status to a private CloudKit database in **your own iCloud account**: its name, model and macOS version, battery readings (charge, health, cycles, capacity, power, temperature and the adapter), the last day of charge, Keep Awake state, Low Power Mode and battery protection settings, heat, whether the lid is closed, the network type and the name of the Wi‑Fi network or Personal Hotspot it is connected to.
- When you ask for it on the iPhone, the Mac also adds the battery level of connected accessories and the apps using the most energy, by name.
- Your iPhone reads that status and writes short-lived commands back, such as starting or stopping Keep Awake. A command carries this iPhone’s name as it appears in the app, so the Mac can show which iPhone started a session.
- The status and commands are stored in encrypted fields. We have no access to your private iCloud database. Apple’s handling of iCloud data is described in Apple’s privacy policy.
- Alerts the Mac sends to your iPhone, such as Keep Awake ending or the battery running low, carry one short sentence that push notifications cannot encrypt, without the Mac’s name or network. Your iPhone adds the Mac’s name itself. The Mac deletes them after 10 minutes.
- Alerts such as “Keep Awake ended” are delivered as push notifications through Apple. Their text names the event and, where relevant, a battery percentage or a remaining time. It does not include the Mac’s name or network.
- Turning sharing off removes the Mac’s record from iCloud. You can also remove a Mac from the iPhone app, or manage the app’s iCloud data in your Apple Account settings.

## Data That Stays on Your iPhone

Battistics Remote reads what iOS shares with apps: battery level and state, Low Power Mode, thermal state, storage, network type and time since restart. It keeps a 24-hour history of the battery level and any battery health or cycle count you type in. All of this stays on your iPhone and is deleted when you delete the app.

## Location

Battistics on the Mac reads the name of the Wi‑Fi network or Personal Hotspot it is connected to, so the iPhone can show it. It takes the name from macOS, and asks for Location access only when macOS will not give it otherwise. Battistics never reads or stores your location. Battistics Remote does not request Location.

## Network Activity

- **Software updates (Mac):** Battistics checks for updates through GitHub, where the app is published. This request contains the app version, like any download. You can turn automatic checks off in Battistics › About.
- **iCloud:** used only when you share a Mac with your iPhone, as described above.
- Battistics makes no other network requests.

## Third-Party Services

Battistics uses Apple’s iCloud (CloudKit and push notifications) when you choose to share a Mac with your iPhone, and GitHub for software updates on the Mac. It contains no third-party analytics, advertising or tracking code.

## Children’s Privacy

Battistics does not collect any information from anyone, including children under the age of 13.

## Your Rights

Since we do not collect any data, there is no personal information to access, correct, delete or port. Data on your devices and in your own iCloud account is under your control and can be removed as described above.

## Contact Information

If you have questions about this privacy policy or Battistics:

- **Email**: [battistics@doguyilmaz.com](mailto:battistics@doguyilmaz.com)
- **Website**: [battistics.doguyilmaz.com](https://battistics.doguyilmaz.com)
- **GitHub Issues**: [https://github.com/doguyilmaz/battistics/issues](https://github.com/doguyilmaz/battistics/issues)

## Changes to This Policy

If this policy changes, the “Last Updated” date above will change and the new version will be posted on this page.
