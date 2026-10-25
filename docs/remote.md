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

### Single-Page Dashboard
- **Proportional Viewport Layout:** Uses `GeometryReader` + `.frame(minHeight: proxy.size.height)` so the dashboard fills the iPhone 16e screen proportionally from top to bottom without unnecessary scrolling.
- **Zero Layout Shift (No Jumping):**
  - `KeepAwakeCard` keeps one height (`76pt` controls, `30pt` two-line feedback slot, `40pt` action button) whether Keep Awake is idle or active.
  - Errors, battery warnings and mode subtitles swap inside that slot and clear when the user changes mode or duration, or starts or stops a session.
  - `PocketModeDock` is always anchored at the bottom (`64pt` min height), morphing between Hotspot Paired, Wi‑Fi / Smart Tips, and Offline states without pushing or pulling other cards vertically.

### Bag Mode, Wi‑Fi and Hotspot
Because Macs do not have cellular modems, a Mac on stationary Wi‑Fi will lose internet as soon as it leaves the building in a bag:
- **"Bag Ready" Only on Hotspot:**
  - The Lid tile, bottom dock and widgets only report `Bag Ready` when the Mac answers, `status.network == .hotspot` and `closedLidAllowed == true` (`SharedSnapshot.bagReady` for widgets).
  - When on Wi‑Fi with the lid closed, the Lid tile reports `Lid · Clamshell` (on power adapter) or `Lid · On Wi‑Fi` (on battery).
  - Tapping `Bag 1h` in `PocketModeDock` automatically selects `Lid Closed` mode and `1h` duration in `KeepAwakeCard` and starts the session.
- **Wi‑Fi Closed-Lid Confirmation Dialog:**
  - If the user selects `Lid Closed` mode and taps Start while the Mac is on Wi‑Fi (`network != .hotspot`), the app presents a confirmation dialog explaining that stationary Wi‑Fi will drop when leaving range, offering:
    1. **`How to Turn On Hotspot`** (explains Settings › Personal Hotspot; iOS has no public link to that screen)
    2. **`Start on Current Wi‑Fi`** (for desk clamshell or portable Wi‑Fi routers)
    3. **`Cancel`**
- **Smart User-Friendly Notifications & Rolling Local Watchdog (`Notifications.swift` & `RemoteAlert.swift`):**
  1. **Unplugged on Wi‑Fi Alert (`unpluggedWithoutHotspot`):** When the Mac is unplugged from power (`onAdapter: true -> false`) during an active Keep Awake session while still on Wi‑Fi, the iPhone immediately reminds the user to turn on Personal Hotspot before putting the Mac in a bag.
  2. **Closed Lid on Battery without Hotspot (`closedLidWithoutHotspot`):** When the Mac lid closes on battery during an active session while not on Hotspot, the iPhone alerts the user to connect to Hotspot if they are taking the Mac with them.
  3. **Rolling local watchdog (`syncWatchdog`):** While a session runs, the Mac writes every 2 minutes (`RemoteStatus.sessionHeartbeat`) and the iPhone schedules a local notification at `status.staleDate` (4 missed writes) plus 45 s. Each fresh reading pushes it forward and removes an already delivered one. The dashboard, widgets (a timeline entry at `staleDate`) and the Live Activity (`ActivityContent.staleDate`) switch to offline at that same instant, so no surface says "disconnected" while another still shows the Mac online.
- **Interactive Rotating Mobility Tips:**
  - When on Wi‑Fi, tapping the text area of the bottom `PocketModeDock` cycles through practical tips (`Auto-Join Hotspot`, `Closed Bag Heat / Thermal Care`, and `Until Turned Off`).

### Remote Mac Power Mode, Display Sleep & Cycle Count (`BatteryCard`)
- **Power Mode Menu:** Top-right capsule inside `BatteryCard` displays the Mac's active Low Power Mode state or configured policy (`LPM Battery`, `LPM Off`, `Low Power`). Tapping opens a menu to set macOS Low Power Mode (`Never`, `Only on Battery`, `Only on Power Adapter`, `Always`) via `BattisticsPowerHelper` without password prompts, or trigger **`Sleep Mac Display Now`** (`pmset displaysleepnow`).
- **Interactive Health & Cycle Count Pill:** Displays `86%` with `Health · <N>c` subtitle; tapping toggles between health percentage and cycle count as the primary metric.
- **Offline / Sleeping Mac State:** When the Mac is unreachable or offline, `BatteryCard` shows "Offline (XX%)" with a clear "Last reported · X ago" timestamp instead of live charging animations. The power mode menu and keep awake controls are cleanly disabled with an informative "Mac is Offline" button and feedback indicator.

### Zero-Permission SSID & Hotspot Network Resolution
- On macOS 14/15/26, CoreWLAN `interface()?.ssid()` requires Location Services authorization. Battistics implements zero-permission fallback extraction directly from macOS `SCDynamicStore` by parsing the 802.11 Information Element tag #0 from `CachedScanRecord`, resolving the active Wi-Fi SSID immediately without prompts.
- When tethered to Personal Hotspot, `RemoteAccessModel` and `RemoteStatus` automatically resolve the paired iPhone's name (e.g. `Dogu’s iPhone 16e`).
- iOS has no public URL for Wi‑Fi or Personal Hotspot settings (`App-prefs:` is private API and fails App Review), so the Network tile and Hotspot buttons show short instructions instead (`hotspotHelp`).

### Setup & Connection Diagnostics (`SetupIntro.swift`)
- When no Macs have reported to iCloud yet, `SetupIntro` shows:
  1. **This iPhone Instant Launch:** A prominent card lets the user immediately open their local iPhone battery, thermal, voltage, and hardware telemetry dashboard.
  2. **Mac App Links & AirDrop Share:** Direct buttons to download Battistics for Mac or share the link with their Mac via AirDrop with one tap.
  3. **Live Diagnostics:** Interactive iCloud authentication status check, network availability, and Mac records probe.
  4. **Troubleshooting Guide:** Built-in guidance for matching Apple IDs, waking sleeping Macs, and configuring iCloud Drive.

### Blueprint Widget Showcase (`PhoneWidgetSettingsView`)
- In `SettingsView › Widgets & Lock Screen`, all widgets are displayed inside architectural Blueprint Containers (`BlueprintCard`):
  - Home Screen cards share one height with size badges (`SMALL · 2×2`, `MEDIUM · 4×2`, `LARGE · 4×4`) and live previews.
  - Lock Screen cards share one height with badges (`RECTANGULAR`, `CIRCULAR`, `INLINE`).
  - Interactive options (Layout, Telemetry focus, SSID toggle) update the live blueprint previews in real time.

### Solid App Icons & Dynamic Theme Synchronization
- Alternate app icons (`batbattery`, `gauge`, `stats`) have no alpha channel, so SpringBoard draws no white edges. The picker reads `UIApplication.alternateIconName` and only marks an icon selected after iOS confirms the change.
- `PhoneThemeManager` is the only theme mechanism: it sets `window.overrideUserInterfaceStyle`, which also reaches presented sheets (`preferredColorScheme(nil)` never returns a sheet to the system appearance).

---

## 3. Widgets & Live Activity (`Sources/BattisticsPhoneWidgets`)

- **Separation of Families:** `MacWidget` is restricted to Home Screen (`.systemSmall`, `.systemMedium`, `.systemLarge`), while `MacLockScreenDetailWidget` is dedicated to Lock Screen (`.accessoryRectangular`, `.accessoryCircular`, `.accessoryInline`), resolving widget picker duplicate listings.

- **Lock Screen Live Activity (`LockScreenLiveActivityView`):**
  - **Row 1:** Mac name and the power badge (percent, watts, charging or Low Power color).
  - **Row 2:** One headline that merges mode and lid (`Lid closed`, `Ready to close lid`, `Screen On · Lid closed`), the network with its name, and the countdown or `Until stopped` timer.
  - **Row 3:** `Updated 2 min ago`, or `No update since 10:42` once `offline` is set or `context.isStale`, and the **`Stop`** button.
- **Lock Screen & Home Screen Widgets:** `.accessoryInline`, `.accessoryCircular`, `.accessoryRectangular`, `.systemSmall`, and `.systemMedium` widgets with interactive `Keep Awake 1h` and `Stop` buttons.

---

## 4. Verified Only in Simulator, Pending on a Real Device

- Mac and iPhone on the same personal Apple ID through CloudKit (needs the Mac App ID with the iCloud container).
- Silent push wake-ups and the watchdog notification while the app is suspended.
- Live Activity offline/stale rendering and the Stop button from the Lock Screen and Dynamic Island.
- Widget offline entry at `staleDate`, Hotspot detection and Bag Ready on a real Personal Hotspot.
- Alternate icons on the Home Screen and app switcher.

---

## 5. Roadmap & Recommendations (Future Sessions)

1. **Bonjour / Peer-to-Peer Local Fast Path (`NWBrowser` + `NWListener`):** Direct local connection when Mac and iPhone share Personal Hotspot or Wi‑Fi for sub-100ms updates and offline-cellular hotspot control.
2. **iOS 18+ Control Center & Action Button Toggle (`ControlWidget`):** One-tap Keep Awake / Pocket Mode toggle from Control Center or the iPhone Action Button.
3. **Auto-Join Remembered iPhone Hotspot on Mac (`CoreWLAN` Fallback):** Optional automatic association to the user's iPhone Hotspot SSID if Wi‑Fi drops during an active Keep Awake session.
4. **Charge Target & Bag Temperature Threshold Alerts:** Custom one-tap alerts from the iPhone (for example, notify at 80% charge or if bag temperature exceeds 42°C).
5. **StandBy Mode & Apple Watch Smart Stack Companion:** Full-bleed StandBy desk energy display and watchOS Smart Stack widget.
6. **Mac Bluetooth Peripheral Battery Forwarding:** Surface low-battery warnings on the iPhone when a Mac keyboard, trackpad, or headphones drop below 15%.
