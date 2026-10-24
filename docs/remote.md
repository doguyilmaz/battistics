# Battistics Remote Companion (`BattisticsPhone` & `BattisticsRemote`)

Battistics Remote is a single-page iPhone dashboard, Widget suite, and Live Activity experience for monitoring and controlling one or more Macs that may be on your desk or closed in your bag.

---

## 1. Architecture & CloudKit Sync (`Sources/BattisticsRemote`)

Connection happens through the user's private iCloud database (**CloudKit** container `iCloud.com.doguyilmaz.Battistics`). There is no third-party server, no open port on the Mac, and no manual pairing code. Any Mac and iPhone signed into the same personal Apple ID (`Dogu Kaan Yilmaz`, Team `5MYT4VYJFC`) automatically discover each other.

- **Off by default:** `Battistics › iPhone › Show this Mac in Battistics Remote` starts sharing. Turning it off deletes the Mac's `MacStatus` record so it immediately disappears from all paired iPhones.
- **Encrypted CloudKit Records:**
  - A custom `Remote` record zone (`CKRecordZone.ID(zoneName: "Remote")`) stores one `MacStatus` record per Mac (`mac-<deviceID>`) and short-lived `Command` records (`cmd-<uuid>`) sent from iPhones.
  - All payloads are serialized with `RemoteWire` into `record.encryptedValues["payload"]`, encrypted end-to-end via the user's iCloud Keychain.
  - `RemoteCloud` caches fetched and saved `CKRecord` metadata (`statusRecords`) so subsequent updates mutate the existing record cleanly, and verifies per-record `saveResults`.
- **Real-Time Triggers & Fast Command Polling:**
  - The Mac publishes immediately when any watched state changes: Keep Awake session, battery %, charging/adapter state, power wattage, thermal pressure, macOS Low Power Mode (`NSProcessInfoPowerStateDidChange`), network interface/SSID, or lid state (`AppleClamshellState`).
  - While awake, `RemoteAccessModel` polls the CloudKit zone every 4 seconds so phone commands execute within seconds even when macOS throttles silent push delivery.
  - When `Allow closed-lid sessions from iPhone` is enabled on the Mac, `RemoteAccessModel` automatically prepares and registers `BattisticsPowerHelper` (`prepareForLidSleep()`) so closed-lid sessions started from the phone work without requiring manual helper restarts.

---

## 2. iPhone Single-Page Dashboard & UX Rules (`Sources/BattisticsPhone`)

### Full-Screen, Zero-Jump Single-Page Dashboard
- **Proportional Viewport Layout:** Uses `GeometryReader` + `.frame(minHeight: proxy.size.height)` so the dashboard fills the iPhone 16e screen proportionally from top to bottom without unnecessary scrolling.
- **Zero Layout Shift (No Jumping):**
  - `KeepAwakeCard` maintains an identical height (`76pt` control body + `18pt` single-line feedback slot + `40pt` action button) whether Keep Awake is idle or active.
  - Error messages, battery warnings, and mode subtitles swap inside the fixed `18pt` feedback slot and clear automatically whenever the user changes mode, duration, or starts/stops a session.
  - `PocketModeDock` is always anchored at the bottom (`64pt` min height), morphing between Hotspot Paired, Wi‑Fi / Smart Tips, and Offline states without pushing or pulling other cards vertically.

### Honest Bag Mode vs. Wi‑Fi Logic & Smart Mobility Protection
Because Macs do not have cellular modems, a Mac on stationary Wi‑Fi will lose internet as soon as it leaves the building in a bag:
- **"Bag Ready" Only on Hotspot:**
  - The Lid tile and bottom dock only report `Lid · Bag ready` / `Pocket Mode Ready` when `status.network == .hotspot` and `closedLidAllowed == true`.
  - When on Wi‑Fi with the lid closed, the Lid tile reports `Lid · Clamshell` (on power adapter) or `Lid · On Wi‑Fi` (on battery).
  - Tapping `Bag 1h` in `PocketModeDock` automatically selects `Lid Closed` mode and `1h` duration in `KeepAwakeCard` and starts the session.
- **Wi‑Fi Closed-Lid Confirmation Dialog:**
  - If the user selects `Lid Closed` mode and taps Start while the Mac is on Wi‑Fi (`network != .hotspot`), the app presents a confirmation dialog explaining that stationary Wi‑Fi will drop when leaving range, offering:
    1. **`Start & Open Hotspot Settings`** (starts the session and jumps directly to iOS Personal Hotspot settings)
    2. **`Start on Current Wi‑Fi`** (for desk clamshell or portable Wi‑Fi routers)
    3. **`Cancel`**
- **Smart User-Friendly Notifications & Rolling Local Watchdog (`Notifications.swift` & `RemoteAlert.swift`):**
  1. **Unplugged on Wi‑Fi Alert (`unpluggedWithoutHotspot`):** When the Mac is unplugged from power (`onAdapter: true -> false`) during an active Keep Awake session while still on Wi‑Fi, the iPhone immediately reminds the user to turn on Personal Hotspot before putting the Mac in a bag.
  2. **Closed Lid on Battery without Hotspot (`closedLidWithoutHotspot`):** When the Mac lid closes on battery during an active session while not on Hotspot, the iPhone alerts the user to connect to Hotspot if they are taking the Mac with them.
  3. **Rolling Local Dead-Man's Switch Watchdog (`syncWatchdog`):** While a Keep Awake session is running on the Mac, the iPhone schedules a rolling local `UNTimeIntervalNotificationTrigger` (10 minutes when mobile/on battery without Hotspot, 18 minutes otherwise). Each fresh CloudKit check-in pushes the timer forward. If the Mac loses internet in a bag and stops reporting, the local notification fires even when the iPhone app is suspended, warning the user that their Mac lost connection and tasks needing internet may have paused.
- **Interactive Rotating Mobility Tips:**
  - When on Wi‑Fi, tapping the text area of the bottom `PocketModeDock` cycles through practical tips (`Auto-Join Hotspot`, `Closed Bag Heat / Thermal Care`, and `2-Tap ∞ Until Turned Off`).

### Ambient Energy & Connection Themes (`PowerPalette` & `AmbientEnergyBackdrop`)
1. **Charging / Adapter (`PowerPalette.charging`, Emerald Green):** Radial light rays, green border glow, pulsing `bolt.fill`, and live wattage (`+42W`, `65W`).
2. **Low Power Mode (`PowerPalette.lowPower`, Warm Amber):** Amber light rays, amber battery tint, and `leaf.fill` `Low Power` capsule badge.
3. **Normal Battery Discharge:** Clean neutral background.
4. **Hotspot Paired / Pocket Mode (`PowerPalette.hotspot`, Electric Cyan):** Cyan wireless aura, `Hotspot Paired` header indicator, and `Bag 1h` quick action in the bottom dock.

---

## 3. Widgets & Live Activity (`Sources/BattisticsPhoneWidgets`)

- **3-Row Non-Truncating Lock Screen Live Activity (`LockScreenLiveActivityView`):**
  - **Row 1:** Full Mac name (`layoutPriority(1)`) on the left, power/battery capsule (`100%`) on the right.
  - **Row 2:** Keep Awake mode (`Screen Off`, `Screen On`, `Lid Closed`) + lid state + network/SSID on the left; right-aligned countdown or elapsed timer (`∞ Until stopped`) with fixed trailing width on the right so timer boxes never crush or truncate the left labels.
  - **Row 3:** Power status on the left, interactive orange **`Stop`** button (`StopKeepAwakeLiveIntent`) on the right.
- **Lock Screen & Home Screen Widgets:** `.accessoryInline`, `.accessoryCircular`, `.accessoryRectangular`, `.systemSmall`, and `.systemMedium` widgets with interactive `Keep Awake 1h` and `Stop` buttons.

---

## 4. Roadmap & Recommendations (Future Sessions)

1. **Bonjour / Peer-to-Peer Local Fast Path (`NWBrowser` + `NWListener`):** Direct local connection when Mac and iPhone share Personal Hotspot or Wi‑Fi for sub-100ms updates and offline-cellular hotspot control.
2. **iOS 18+ Control Center & Action Button Toggle (`ControlWidget`):** One-tap Keep Awake / Pocket Mode toggle from Control Center or the iPhone Action Button.
3. **Auto-Join Remembered iPhone Hotspot on Mac (`CoreWLAN` Fallback):** Optional automatic association to the user's iPhone Hotspot SSID if Wi‑Fi drops during an active Keep Awake session.
4. **Charge Target & Bag Temperature Threshold Alerts:** Custom one-tap alerts from the iPhone (for example, notify at 80% charge or if bag temperature exceeds 42°C).
5. **StandBy Mode & Apple Watch Smart Stack Companion:** Full-bleed StandBy desk energy display and watchOS Smart Stack widget.
6. **Mac Bluetooth Peripheral Battery Forwarding:** Surface low-battery warnings on the iPhone when a Mac keyboard, trackpad, or headphones drop below 15%.
