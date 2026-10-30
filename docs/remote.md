# Battistics Remote

The iPhone companion (`Sources/BattisticsPhone`, widgets in `Sources/BattisticsPhoneWidgets`, shared views in `Sources/BattisticsPhoneShared`) shows one or more Macs and controls Keep Awake on them. The wire contract lives in `Sources/BattisticsRemote`.

## Sync

- Everything goes through the user's private CloudKit database, container `iCloud.com.doguyilmaz.Battistics`, zone `Remote`. No server, no open port, no pairing code: a Mac and an iPhone on the same Apple Account see each other.
- One `MacStatus` record per Mac and short-lived `Command` records from phones. Payloads are JSON (`RemoteWire`) in `encryptedValues["payload"]`.
- A Mac's record is named by a sharing ID kept with its hardware UUID, so a Mac set up from another Mac's backup gets its own record instead of answering for that Mac.
- Sharing is off by default (`Battistics › iPhone › Show this Mac in Battistics Remote`). Turning it off deletes the Mac's record; a publish already in flight deletes it again when it lands.
- Each queued command gets its own answer published before the next one runs.
- A phone that stops waiting (no answer within `RemoteRequest.answerWait`, a fetch error or a cancelled intent) deletes its command first, so a late Mac does not run it. If that delete fails, the Mac still drops any command older than `RemoteRequest.lifetime`, a minute. A Mac also deletes expired commands addressed to Macs that no longer exist.
- Turning sharing off while offline keeps retrying the delete until it lands, so phones never keep a ghost of the Mac.
- Details › Remove Mac, offered while a Mac is not answering, deletes its record for an erased or sold Mac. A Mac that still shares sees the deletion in its next change read and publishes again at once.
- A status or command written by a newer build stays readable: an unknown operation is answered as an invalid request ("Update Battistics"), and a status the phone cannot decode keeps that Mac's last reading instead of removing it.
- The Mac polls with `RemoteCloud.fetchChanges()` (change token, deltas only): every 4 s for 2 minutes after a command, every 15 s otherwise, also during a Keep Awake session. macOS throttles silent pushes, so a push only triggers an extra poll.
- `publish` builds the cheap status first and compares it with the last one sent (`RemoteStatus.differsNoticeably`: the read time, watts, temperature, voltage, current, mAh and small moves of the time-left estimate do not count). History and `pmset` are read only when something changed or the heartbeat is due. The heartbeat is published even when reading commands fails, and CloudKit's `retryAfter` is honoured.
- Handled command ids are remembered until their records are deleted, so a failed delete never runs a command twice.
- A full read without this Mac's record (a lost zone, or one another device recreated) makes the Mac publish at once instead of waiting for the heartbeat.
- Before the Mac sleeps, shuts down or restarts, `SleepWatcher` (IOKit `IORegisterForSystemPower`) holds the power change for up to 8 seconds. It ends Keep Awake, then publishes `sleptAt`, so the phone gets one ended alert and drops the lock-screen countdown. A status that still carries a session pushes `.sleptDuringSession` once. Wake clears `sleptAt` and does not start the session again.
- `RemoteRequest.Operation.sleep` ends any session and waits for a closed-lid session to give back the sleep setting. It answers with a failure while macOS sleep is turned off, otherwise answers and then runs `pmset sleepnow`.

## Freshness

- The Mac writes `heartbeatSeconds` into every status: 120 s during a session, 600 s otherwise. A phone treats a reading as stale after 4 (session) or 2 missed heartbeats (`RemoteStatus.staleDate`). Only a real fetch may call a Mac offline.
- iOS throttles the silent pushes that wake the phone, so surfaces that cannot fetch wait longer:
  - The watchdog notification ("No word from the Mac since 10:42") fires after `RemoteStatus.watchdogDelay`: just past the stale window once background pushes have arrived steadily for at least 15 minutes, otherwise up to 30 minutes. `DeliveryCadence` records when background pushes actually arrived.
  - While the watchdog waits longer than the stale window, a passive note ("Last update at 10:42 ...", no sound) lands in Notification Center at `RemoteStatus.quietDelay`. It says only that no update came, and the next fetch removes it whatever it finds.
  - Neither is scheduled when the session ends before the watchdog would fire.
  - Widgets add a timeline entry at `unheardDate` (at least 30 minutes after the reading) that shows the Mac offline.
  - A reading with `sleptAt` is stale at once and shows "Asleep" everywhere a silent Mac shows "Offline"; its Live Activity ends. A timed session that ran out raises no "stopped answering" alert, since the Mac most likely slept before saying so.
  - The newest reading is always saved for widgets, but they reload only for a change they show (`SharedSnapshot.differsNoticeably`) or 15 minutes after the last reload, so background writes do not spend WidgetKit's daily budget.
  - The Live Activity uses `unheardDate` as its stale date, also for timed sessions, and then shows "No update since 10:42". A fetch that finds the Mac asleep or not answering ends it.
- Settings › Notifications › When Charged To reports once when a charging Mac reaches 80, 90 or 100%. It is evaluated on the phone, so it arrives with the next update the phone receives, and re-arms only after the charge falls 5 points below the target or the adapter is unplugged, so a Mac held at a charge limit does not ring on every top-up.
- Alerts about a running session (battery low or running out, unplugged or lid closed away from Hotspot, running hot) carry a Stop Keep Awake button (`AlertActions`). The extension adds it to the Mac's pushes from the collapse id.
- With the app open, an alert shows as a banner unless its Mac is on screen, and always lands in Notification Center.
- Alerts are delivered once per change and awaited before a background task completes. Lid and unplug warnings are cleared when the Mac moves to Hotspot.
- The Mac posts the alerts it can see itself (session ended, battery low or running out, unplugged or lid closed away from Hotspot, running hot, Bag Ready when a closed-lid session reaches Hotspot with the lid still open, and sleeping during a session) as short-lived `Event` records after each publish (`RemoteAlert.pushed`). Phones hold one CloudKit query subscription on `Event` (`remote-alerts`), so iOS shows them straight from the push, without the silent-push throttling and while the app is not running. No server, no cost.
- Push payloads cannot carry encrypted fields, so an `Event` holds only a title and a sentence in the Mac's language and a collapse id; no Mac name, network or reading beyond the percentage or time the alert is about. The Mac deletes them after 10 minutes.
- The phone's notification service extension (`BattisticsPhoneAlerts`) reads the Mac id from the collapse id and adds the Mac's name and its thread from the phone's own copy (`SharedSnapshot.loadAll`), so the name never leaves the device.
- Every Mac pushes its own alerts. A phone whose subscription iCloud has accepted skips those kinds locally and raises only the charge target and "stopped answering"; one whose save iCloud refused, or that found the subscription missing (another iPhone on the account turned alerts off), raises every kind itself. That check runs before alerts are filtered. The collapse id equals the local notification id, so the two replace each other instead of stacking.
- CloudKit does not push a change to the device that made it, so a Mac never shows its own alerts; one that receives another Mac's alert removes it.

## iPhone app

- Native navigation: the title is a menu (`toolbarTitleMenu`) with the Macs, This iPhone and Set Up a Mac. Details is a push, Settings a sheet.
- Mac dashboard, top to bottom: status line, battery (charge, time left, power, health with cycles, temperature, 24 hour chart, power menu with Low Power Mode, Turn Off Mac Display and Put Mac to Sleep, which asks first), Keep Awake (mode, durations including an explicit ∞, one start or stop button; starting and running layouts share one height), Hotspot card (Bag Ready only when the Mac answers, is on Hotspot and allows closed-lid sessions), conditions grid, Accessories & Apps.
- Accessories & Apps is sampled on the Mac only when asked (`RemoteRequest.Operation.inspect`): accessory batteries (IORegistry and `system_profiler`) and the five apps using the most CPU over 3 seconds.
- This iPhone shows only what iOS reports (charge, state, Low Power Mode, heat, storage, time since restart) and the health and cycle count the user copied from Settings, labelled as entered. iOS gives apps neither those values nor the device name.
- From its own readings it adds the last day's charge, how long since it saw the iPhone unplugged and the rate over the last hour (`ChargeRate`), with a time estimate worded as "at this rate". An unplug from before the app ran stays unknown.
- Notification permission is asked when a Mac dashboard first opens, not at launch, and from Settings while it is undecided.
- Theme is applied with `window.overrideUserInterfaceStyle`, which also reaches open sheets.
- `-demo` fills the app with sample Macs and plays commands locally, for Simulator checks without iCloud.

## Widgets, Live Activity, Control

- Home Screen: Mac (small, medium, large), Mac Battery (small, medium) and All Macs (medium, large). Lock Screen: Mac (rectangular, circular, inline) and All Macs (rectangular). Each opens the Mac it shows (`battistics-remote://mac/<id>`). One preference set in Settings › Widgets applies to all of them. The Mac widgets show the Mac picked in the app, or one chosen while editing the widget (`MacWidgetIntent`, `WidgetMac`); their buttons act on that Mac.
- The Live Activity merges mode and lid into one line ("Lid closed", "Ready to close lid") and ends with a freshness line, 30 more minutes and Stop. Its buttons carry the Mac id, so they act on that Mac whichever one the app has selected.
- Keep Mac Awake is a Control Center and Action Button control on iOS 18 (`KeepAwakeControl`). Each placed control has its own mode and duration, set by tapping it while Control Center is in edit mode; iOS gives third-party controls no long-press menu.
- The app icon's menu offers Keep Awake for 1 hour, or Add 30 Minutes and Stop while a session runs (`QuickActions`).
- Shortcuts and Siri: Keep Awake, Add Time, Let Sleep, Check Mac, Mac Low Power, Display Off, Sleep Mac and Open Mac, plus Get Mac Battery Level for automations (`Intents.swift`). Check Mac and Get Mac Battery Level fail with iCloud's error instead of returning a reading kept from before a failed fetch. Each can name the Mac it acts on (`MacEntity`). Check Mac also returns that Mac with its battery level, charging, Keep Awake and whether it answers, read fresh, for automations.
- Add Time (`RemoteRequest.Operation.extend`, 15 minutes to 2 hours) is on the Mac dashboard, the Live Activity (30 minutes), the large widget and Shortcuts. It adds to what is left, up to 12 hours from now, and takes a session over from a terminal or AI task.
- Each Mac kept awake has its own Live Activity, matched by its id, so picking another Mac in the app leaves a running countdown in place and two Macs with the same name never share one.
- A refused or unanswered command from a widget, the Live Activity or the control arrives as a notification, since those surfaces cannot show a reply.
- Starting Keep Awake from a widget, Shortcut or control requires an unlocked iPhone. Stopping from the Live Activity or a Shortcut does not; the Control Center toggle asks in both directions, since a control has one policy.

## Safety

- A closed-lid session started from a phone, timed or open-ended, always stops at 10% battery (or the user's higher stop) and under thermal pressure (`KeepAwakeSafetyPolicy.Configuration.unattended`).
- Requests from a phone never install, re-register or repair the root power helper (`PowerHelperClient.requireCurrent`). Only someone at the Mac does that.
- Low Power Mode changes from the phone go through the installed helper and update the Mac's own power settings view.
- A probe of the helper that times out (it may be inside a pmset run) never invalidates the connection holding a closed-lid lease, and Repair and Remove are disabled while that lease is held.
- If the system-wide `disablesleep` override is on with no closed-lid session, Power shows "Sleep is turned off" with Allow Sleep, which the helper refuses while a lease holds the override.

## Network name

- The Mac reads the Wi‑Fi or Hotspot name through CoreWLAN when Location is allowed and otherwise from the SystemConfiguration scan cache. Location is requested only from the button in the Mac's iPhone pane; every build carries the hardened runtime Location entitlement (`Battistics-Base.entitlements`), without which macOS denies the request. On Hotspot, the network name is the iPhone's name, which is how the phone learns what to call itself.

## Signing and release

- Mac iCloud signing is opt-in: `make run-icloud` sets `BATTISTICS_ENTITLEMENTS` and team `5MYT4VYJFC`. `make build`, the CI test build and `make app` without `PROFILE` have no iCloud and show "not signed for iCloud" in the iPhone pane; a release has it when the profile secret is set. `make build` and the test harnesses write to the same folder, so run `make run-icloud` again after them; a separate folder would move the app away from its registered power helper and Location permission.
- A release reaches iCloud when the `MACOS_PROVISIONING_PROFILE` secret holds the Developer ID profile: `scripts/sign-app.sh` embeds it and signs the app with `Battistics-Release.entitlements` (Production container, production push). Locally, `make app SIGN_IDENTITY=... PROFILE=<path>` does the same. The `MacStatus`, `Command` and `Event` schema is deployed to Production. A Mac and a phone only see each other in the same environment, so a Debug phone build pairs with a Debug Mac build, and the App Store app with a release.

## Verified on a device

- iPhone 16e and a MacBook through the real CloudKit container: readings arrive within seconds; Keep Awake start and stop; an open-ended closed-lid session through the installed helper, showing the 10% unattended stop; Accessories & Apps; a Low Power policy change and its revert; the Live Activity and its Stop button; the Lock Screen widget; the Control Center control in both directions; the Home Screen widget's start button; a 15-minute closed-lid session showing the 10% stop; with the Mac app frozen, the quiet note at the stale window and the alert at about 30 minutes, and the note cleared by the next fetch; the Remote zone deleted from the phone while the Mac ran, with the Mac back on the phone 17 seconds later; the Display Off and Mac Low Power shortcuts from the Shortcuts app; switching the app icon to Gauge and back; the Live Activity's offline state after a fetch found the Mac silent, with the quiet note removed by that fetch; with steady pushes, the alert about 9 minutes after the last reading and no quiet note before it. After Repair of helper build 5: a Low Power change from the phone and its revert, Accessories & Apps, Remove Mac and its return, a terminal closed-lid session restoring sleep, and Allow Sleep clearing a stuck `disablesleep` override without a password. With the notification extension: an alert the Mac pushed, shown on the iPhone under the Mac's name.
