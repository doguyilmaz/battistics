# Battistics Remote Companion (`BattisticsPhone` & `BattisticsRemote`)

Battistics Remote is a compact, single-screen iPhone companion app, Widget suite, and Live Activity experience for monitoring and controlling one or more Macs that may be on your desk or closed in your bag.

---

## 1. Architecture & CloudKit Sync (`Sources/BattisticsRemote`)

Connection happens entirely through the user's private iCloud database (**CloudKit** container `iCloud.com.doguyilmaz.Battistics`). There is no third-party server, no open port on the Mac, and no manual pairing code—any Mac and iPhone signed into the same personal Apple ID (`Dogu Kaan Yilmaz`, Team `5MYT4VYJFC`) automatically discover each other.

- **Off by default:** `Battistics › iPhone › Show this Mac in Battistics Remote` starts sharing. Turning it off deletes the Mac's `MacStatus` record so it immediately disappears from all paired iPhones.
- **Encrypted CloudKit Records:**
  - A custom `Remote` record zone (`CKRecordZone.ID(zoneName: "Remote")`) stores one `MacStatus` record per Mac (`mac-<deviceID>`) and short-lived `Command` records (`cmd-<uuid>`) sent from iPhones.
  - All payloads are serialized with `RemoteWire` (JSON with millisecond timestamps) into `record.encryptedValues["payload"]`, encrypted end-to-end via the user's iCloud Keychain.
  - `RemoteCloud` caches fetched/saved `CKRecord` system metadata (`statusRecords`) so subsequent updates mutate the existing record seamlessly without `ServerRecordChanged` conflicts, and verifies per-record `saveResults`.
- **Real-Time Triggers & Heartbeat:**
  - The Mac publishes immediately when any watched state changes: Keep Awake session, battery %, charging/adapter state, power wattage, thermal pressure, macOS Low Power Mode (`NSProcessInfoPowerStateDidChange`), network interface/SSID, or lid state (`AppleClamshellState`).
  - A 10-minute heartbeat keeps `readAt` fresh; readings older than 20 minutes mark the Mac as `Not answering`.
- **Command Lifecycle & Safety:**
  - The iPhone writes a `Command` record (`start` or `stop`) and watches for `lastCommand.id == request.id` for up to 25 seconds (polling + push wakeup), then deletes the command record so an offline Mac never runs a stale command later.
  - The Mac drops commands older than 2 minutes and polls every 5 minutes as a fallback if silent push delivery is delayed.
  - Sessions started from the iPhone respect all Mac safety guardrails (low-battery warning/stop threshold, thermal pressure auto-stop, and closed-lid helper requirement).

---

## 2. iPhone UI/UX Design System (`Sources/BattisticsPhone`)

### Single-Screen Ergonomics (Zero Unnecessary Scroll on iPhone 16e)
- **Inline Header & Compact Spacing:** Uses `.navigationBarTitleDisplayMode(.inline)` with a custom principal toolbar item (`MacHeaderPicker`) to eliminate the oversized navigation bar gap above the Mac name.
- **Adaptive Scroll Bounce:** `.scrollBounceBehavior(.basedOnSize)` keeps the entire main dashboard (Paired Banner, Battery Card, Keep Awake Card, and 2×2 Status Tiles) fitting comfortably on a single iPhone 16e screen while remaining scrollable if accessibility Dynamic Type sizes are increased.
- **Smooth State Transitions:** State changes in battery percentage, charging wattage, network connection, Keep Awake mode, and duration selection animate with `.spring(response: 0.35, dampingFraction: 0.82)` and `.contentTransition(.numericText())`.

### Ambient Energy & Connection Themes (`PowerPalette` & `AmbientEnergyBackdrop`)
The UI dynamically adapts its ambient background, card borders, and badges to reflect the Mac's real-time power and network state without visual clutter:
1. **Charging / Adapter (`PowerPalette.charging` — Emerald Green):**
   - Animated radial light rays (`EnergyRaysView`) and subtle green border glow on the Battery Card.
   - Pulsing `bolt.fill` badge (`+42W`, `67W adapter`) and green battery bar.
2. **Low Power Mode (`PowerPalette.lowPower` — Warm Amber/Gold):**
   - Detected live on macOS via `ProcessInfo.processInfo.isLowPowerModeEnabled` (`NSProcessInfoPowerStateDidChange`).
   - Warm amber light rays, amber battery tint, and `leaf.fill` `Low Power` capsule badge.
3. **Normal Battery Discharge:**
   - Clean system grouped background with no distracting rays; shifts to orange/red only when crossing the low-battery warning threshold.
4. **Hotspot Paired / Pocket Mode (`PowerPalette.hotspot` — Electric Cyan):**
   - Distinct cyan wireless aura when `status.network == .hotspot` so it never collides with green (charging) or amber (low power).
   - Displays a dedicated **`HotspotPairedBanner`** at the top of the screen:
     - When `closedLidAllowed` is enabled: **"Pocket Mode Ready / Active · Free to go with lid closed"** with a one-tap **`Bag 1h`** quick action to immediately start Closed-Lid Keep Awake for 1 hour.
     - When `closedLidAllowed` is disabled: **"Hotspot Paired · Linked to <SSID> · Ready on the go"**.

### Keep Awake Controls: Short Labels & 2-Step "Until Turned Off" (`∞`)
- **Non-Truncating Segmented Mode Picker:**
  - Uses concise titles that never truncate on compact screens:
    - **`Screen Off`** (*Mac stays awake; display can turn off*)
    - **`Screen On`** (*Mac and display both stay awake*)
    - **`Lid Closed`** (*Stays awake in your bag on battery or adapter*)
  - Displays a 1-line contextual subtitle immediately below the segmented control.
- **2-Step Duration Selection ("Until Turned Off" / `minutes = 0`):**
  - Duration pills: `15m`, `30m`, `1h`, `2h`, `4h`, `8h`.
  - **Tap once** to select a timed duration (e.g. `1h` → button reads `Keep Awake for 1h`).
  - **Tap the active duration pill a second time** to deselect it (`minutes = 0`). All pill backgrounds clear, a `∞ Until turned off` badge appears in the section header, and the primary button switches to **`Keep Awake Until Stopped`** (`infinity` icon).
  - Tapping the `∞ Until turned off` header badge also directly toggles indefinite mode.

### Wi‑Fi & Personal Hotspot SSID + Deep-Link to iOS Hotspot Settings
- **Network Name (SSID) Detection:**
  - On macOS, `NetworkMonitor` queries `CWWiFiClient.shared().interface()?.ssid()` alongside `CLLocationManager` authorization (`NSLocationUsageDescription`).
  - In `Battistics › iPhone` on the Mac, if Wi‑Fi is connected and Location permission has not been granted yet, a `Show Wi‑Fi Network Name` button requests permission so the exact SSID is shared.
  - When on Personal Hotspot (`network == .hotspot`), if macOS Location permission hasn't been granted yet, the iPhone automatically falls back to displaying the iPhone's own hotspot name (`UIDevice.current.name`, e.g., `Dogu’s iPhone 16e`).
- **Hotspot Settings Intent / Deep-Link:**
  - Tapping the **Connection / Hotspot tile** on the main screen (when on Hotspot) or the **Open Personal Hotspot Settings** row in `SettingsView` opens iOS Personal Hotspot settings (`App-Prefs:root=INTERNET_TETHERING` with automatic fallback to `UIApplication.openSettingsURLString`).

### Multi-Device Hub (Multiple Macs & iPhones)
- **Header Switcher (`MacHeaderPicker`):**
  - Always visible in the navigation bar, showing the active Mac's name, live status dot (cyan on Hotspot, green when Keep Awake is active or charging, amber on Low Power, gray when stale), and battery percentage.
  - When multiple Macs are registered on the Apple ID, tapping the header opens a rich menu to switch between Macs or jump straight to device management.
- **Devices Hub in `SettingsView`:**
  - Lists every Mac in the user's CloudKit zone with its live battery %, connection type + SSID, Keep Awake mode, and selection checkmark, plus `"This iPhone"` (`UIDevice.current.name`) which stamps remote commands (`Started from <iPhone name>`).

---

## 3. Lock Screen Widgets, Home Screen Widgets & Live Activity (`Sources/BattisticsPhoneWidgets`)

### Live Activity & Dynamic Island (`KeepAwakeActivityWidget`)
Automatically starts when a Keep Awake session is running on the selected Mac (either started from the iPhone or discovered via CloudKit push/refresh) and updates whenever battery, power, or session state changes:
- **Charging & Power Visuals:**
  - **Charging:** Emerald green accent, pulsing `bolt.fill` symbol effect, live wattage (`+42W`), and green progress bar.
  - **Low Power Mode:** Warm amber accent, `leaf.fill` badge, and amber timer tint.
  - **Hotspot Paired:** Cyan `personalhotspot` badge and SSID/Hotspot indicator.
- **Timed vs. Indefinite (`∞`) Sessions:**
  - Timed sessions show a live countdown (`Text(timerInterval: start...deadline, countsDown: true)`) and a live `ProgressView(timerInterval:)` bar.
  - Indefinite (`Until turned off`) sessions show an `∞` badge alongside a live elapsed timer (`Text(startedAt, style: .timer)`).
- **Interactive Stop Action:**
  - Includes an interactive `StopKeepAwakeLiveIntent` (`LiveActivityIntent`) button right on the Lock Screen banner and Dynamic Island expanded view to stop Keep Awake without opening the app.

### Home Screen Widgets (`.systemSmall` & `.systemMedium`)
- **Small Widget:** Mac name, network/hotspot icon, large color-coded battery percentage, charging wattage / Low Power badge / time remaining, and either the live Keep Awake countdown or a one-tap **`Keep Awake 1h`** interactive button (`StartKeepAwakeLiveIntent`).
- **Medium Widget:** Split layout with full battery & power telemetry on the left (percentage, charging/low-power/hotspot badges, progress bar, network SSID, lid state) and an interactive Keep Awake control panel on the right (live timer + **`Stop`** button when active, or **`Keep Awake 1h`** button when idle).

### Lock Screen Widgets
- **`.accessoryCircular`:** Circular battery gauge with charging bolt (`bolt.fill`), active flame (`flame.fill`), or battery percentage inside.
- **`.accessoryRectangular`:** Mac name + Hotspot/Low Power/Charging icons, battery percentage + time left, and live Keep Awake countdown/mode.
- **`.accessoryInline`:** Compact single-line summary (`Mac · 84% ⚡ · 1:42` or `Mac · 84% · ∞`).

---

## 4. Signing & Running on Physical Devices

- **Personal Account Rule:** Always sign with personal Apple ID team **`5MYT4VYJFC` (`Dogu Kaan Yilmaz`)** and `com.doguyilmaz.Battistics*` bundle identifiers.
- **CloudKit Development Environment:** Both `Sources/BattisticsApp/Support/Battistics.entitlements` and `Sources/BattisticsPhone/BattisticsPhone.entitlements` set `com.apple.developer.icloud-container-environment` to `Development` for debug builds so both apps talk to the same CloudKit Development schema.
- **Commands:**
  - Run Mac app with iCloud signing: `make run-icloud`
  - Build & install iPhone app on connected iPhone:
    ```bash
    xcodegen generate
    xcodebuild -project Battistics.xcodeproj -scheme BattisticsPhone -destination 'id=<DEVICE_UDID>' -derivedDataPath .build/xcode -allowProvisioningUpdates build
    xcrun devicectl device install app --device <DEVICE_UDID> ".build/xcode/Build/Products/Debug-iphoneos/Battistics Remote.app"
    ```

---

## 5. Roadmap & High-Value Recommendations (Future Sessions)

To make Battistics Remote even more powerful in upcoming iterations, the following high-leverage features are designed and ready to build next:

1. **Bonjour / Peer-to-Peer Local Fast Path (`NWBrowser` + `NWListener`):**
   - When the Mac and iPhone share the same Wi‑Fi or Personal Hotspot (`network == .hotspot`), establish a local peer-to-peer connection over Bonjour (`_battistics._tcp`) authenticated with a shared key stored in CloudKit's encrypted record.
   - **Benefit:** Sub-100ms instant live wattage/temperature streaming and instant command execution even if cellular internet inside a train/plane is unavailable while tethered to Hotspot.
2. **iOS 18+ Control Center & Action Button Control (`ControlWidget`):**
   - Add a `ControlWidgetToggle` (`Keep Mac Awake` / `Pocket Mode 1h`) in `BattisticsPhoneWidgets` so the user can toggle Keep Awake or Closed-Lid Pocket Mode directly from the iPhone Control Center, Lock Screen bottom corner buttons, or the iPhone 16e Action Button.
3. **Auto-Join Remembered iPhone Hotspot on Mac (`CoreWLAN` Fallback):**
   - If the Mac is in an active Keep Awake session and loses Wi‑Fi, optionally trigger a scan/associate to the user's known iPhone Personal Hotspot SSID via `CWInterface.associate(to:password:)`.
4. **Charge Target & Thermal Alerts on iPhone ("Ready to Unplug — 80% / 100%"):**
   - Let the user set a quick one-off notification target from the iPhone (e.g., *"Notify me when Mac reaches 80%"* or *"Alert if Mac inside bag exceeds 42°C"*), delivered via CloudKit push + time-sensitive notification.
5. **StandBy Mode & Apple Watch Smart Stack Companion:**
   - Optimize `.systemSmall` / `.systemLarge` widget layouts with `containerBackground` vibrancy for iPhone **StandBy** mode on a desk charger (turning the iPhone into a live desk energy dashboard for the Mac).
6. **Mac Bluetooth Peripheral Battery Forwarding:**
   - Include low-battery summaries for Magic Keyboard, Magic Trackpad, and AirPods connected to the Mac inside `RemoteStatus`, surfacing a subtle pill on the iPhone when a Mac accessory drops below 15%.
