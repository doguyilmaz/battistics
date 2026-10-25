# Battistics Remote

The iPhone companion (`Sources/BattisticsPhone`, widgets in `Sources/BattisticsPhoneWidgets`, shared views in `Sources/BattisticsPhoneShared`) shows one or more Macs and controls Keep Awake on them. The wire contract lives in `Sources/BattisticsRemote`.

## Sync

- Everything goes through the user's private CloudKit database, container `iCloud.com.doguyilmaz.Battistics`, zone `Remote`. No server, no open port, no pairing code: a Mac and an iPhone on the same Apple Account see each other.
- One `MacStatus` record per Mac and short-lived `Command` records from phones. Payloads are JSON (`RemoteWire`) in `encryptedValues["payload"]`.
- Sharing is off by default (`Battistics › iPhone › Show this Mac in Battistics Remote`). Turning it off deletes the Mac's record; a publish already in flight deletes it again when it lands.
- Each queued command gets its own answer published before the next one runs.
- The Mac polls with `RemoteCloud.fetchChanges()` (change token, deltas only): every 4 s during a Keep Awake session or for 2 minutes after a command, every 15 s otherwise. macOS throttles silent pushes, so a push only triggers an extra poll.
- `publish` builds the cheap status first and compares it with the last one sent. History and `pmset` are read only when something changed or the heartbeat is due. The heartbeat is published even when reading commands fails, and CloudKit's `retryAfter` is honoured.
- Handled command ids are remembered until their records are deleted, so a failed delete never runs a command twice.
- A full read without this Mac's record (a lost zone, or one another device recreated) makes the Mac publish at once instead of waiting for the heartbeat.

## Freshness

- The Mac writes `heartbeatSeconds` into every status: 120 s during a session, 600 s otherwise. A phone treats a reading as stale after 4 (session) or 2 missed heartbeats (`RemoteStatus.staleDate`). Only a real fetch may call a Mac offline.
- iOS throttles the silent pushes that wake the phone, so surfaces that cannot fetch wait longer:
  - The watchdog notification ("No word from the Mac since 10:42") fires after `RemoteStatus.watchdogDelay`: just past the stale window once background pushes have arrived steadily for at least 15 minutes, otherwise up to 30 minutes. `DeliveryCadence` records when background pushes actually arrived.
  - While the watchdog waits longer than the stale window, a passive note ("Last update at 10:42 ...", no sound) lands in Notification Center at `RemoteStatus.quietDelay`. It says only that no update came, and the next fetch removes it whatever it finds.
  - Neither is scheduled when the session ends before the watchdog would fire.
  - Widgets add a timeline entry at `unheardDate` (at least 30 minutes after the reading) that shows the Mac offline.
  - The Live Activity uses `unheardDate` as its stale date, also for timed sessions, and then shows "No update since 10:42". It shows the Mac as offline only after a fetch confirmed it.
- Settings › Notifications › When Charged To reports once when a charging Mac reaches 80, 90 or 100%. It is evaluated on the phone, so it arrives with the next update the phone receives.
- Alerts are delivered once per change and awaited before a background task completes. Lid and unplug warnings are cleared when the Mac moves to Hotspot.

## iPhone app

- Native navigation: the title is a menu (`toolbarTitleMenu`) with the Macs, This iPhone and Set Up a Mac. Details is a push, Settings a sheet.
- Mac dashboard, top to bottom: status line, battery (charge, time left, power, health with cycles, temperature, 24 hour chart, Low Power menu with Turn Off Mac Display), Keep Awake (mode, durations including an explicit ∞, one start or stop button; starting and running layouts share one height), Hotspot card (Bag Ready only when the Mac answers, is on Hotspot and allows closed-lid sessions), conditions grid, Accessories & Apps.
- Accessories & Apps is sampled on the Mac only when asked (`RemoteRequest.Operation.inspect`): accessory batteries (IORegistry and `system_profiler`) and the five apps using the most CPU over 3 seconds.
- This iPhone shows only what iOS reports (charge, state, Low Power Mode, heat, storage, time since restart) and the health and cycle count the user copied from Settings, labelled as entered. iOS gives apps neither those values nor the device name.
- Notification permission is asked on the first Keep Awake start, not at launch.
- Theme is applied with `window.overrideUserInterfaceStyle`, which also reaches open sheets.
- `-demo` (Debug builds only) fills the app with sample Macs and plays commands locally, for Simulator checks without iCloud.

## Widgets, Live Activity, Control

- Home Screen: Mac (small, medium, large) and Mac Battery (small, medium). Lock Screen: rectangular, circular, inline. One preference set in Settings › Widgets applies to all of them.
- The Live Activity merges mode and lid into one line ("Lid closed", "Ready to close lid") and ends with a freshness line and Stop.
- Keep Mac Awake is a Control Center and Action Button control on iOS 18 (`KeepAwakeControl`).
- Shortcuts and Siri: Keep Awake, Let Sleep, Check Mac and Display Off (`Intents.swift`).
- Starting Keep Awake from a widget, Shortcut or control requires an unlocked iPhone. Stopping from the Live Activity or a Shortcut does not; the Control Center toggle asks in both directions, since a control has one policy.

## Safety

- A closed-lid session started from a phone, timed or open-ended, always stops at 10% battery (or the user's higher stop) and under thermal pressure (`KeepAwakeSafetyPolicy.Configuration.unattended`).
- Requests from a phone never install, re-register or repair the root power helper (`PowerHelperClient.requireCurrent`). Only someone at the Mac does that.
- Low Power Mode changes from the phone go through the installed helper and update the Mac's own power settings view.

## Network name

- The Mac reads the Wi‑Fi or Hotspot name through CoreWLAN when Location is allowed and otherwise from the SystemConfiguration scan cache. Location is requested only from the button in the Mac's iPhone pane; every build carries the hardened runtime Location entitlement (`Battistics-Base.entitlements`), without which macOS denies the request. On Hotspot, the network name is the iPhone's name, which is how the phone learns what to call itself.

## Signing and release

- Mac iCloud signing is opt-in: `make run-icloud` sets `BATTISTICS_ENTITLEMENTS` and team `5MYT4VYJFC`. CI, `make build`, `make app` and Developer ID builds have no iCloud and show "not signed for iCloud" in the iPhone pane. `make build` and the test harnesses write to the same folder, so run `make run-icloud` again after them; a separate folder would move the app away from its registered power helper and Location permission.
- A release with iCloud needs: a Developer ID provisioning profile with iCloud and Push embedded in the app, release entitlements with `aps-environment` production and container environment Production, `scripts/sign-app.sh` passing `--entitlements` for the app, the `MacStatus` and `Command` schema deployed to Production in CloudKit Console, and phone and Mac builds in the same environment.

## Verified on a device

- iPhone 16e and a MacBook through the real CloudKit container: readings arrive within seconds; Keep Awake start and stop; an open-ended closed-lid session through the installed helper, showing the 10% unattended stop; Accessories & Apps; a Low Power policy change and its revert; the Live Activity and its Stop button; the Lock Screen widget; the Control Center control in both directions; the Home Screen widget's start button; a 15-minute closed-lid session showing the 10% stop; with the Mac app frozen, the quiet note at the stale window and the alert at about 30 minutes, and the note cleared by the next fetch; the Remote zone deleted from the phone while the Mac ran, with the Mac back on the phone 17 seconds later; the Display Off shortcut from the Shortcuts app; switching the app icon to Gauge and back.

## Verified only in Simulator or tests

- The adaptive watchdog with steady background pushes (only the throttled case ran on a device).
- The Live Activity's offline line after a fetch confirmed the Mac gone (rendered in Simulator; the stale line showed on a device).

## Considered and not built

- Visible alerts sent by the Mac through a CloudKit query subscription would arrive without the silent-push throttling. Subscriptions belong to the account, so the Mac app would receive and display the same alerts. Revisit with a record field the subscription can filter on once it can be indexed in CloudKit Console.
