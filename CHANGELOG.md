# Changelog

## 1.0.2

- Native macOS 26 app icon (Icon Composer format): the update dialog and
  launchers no longer show the icon shrunken on a light tile
- Legacy icon set refitted to the standard 824/1024 grid for macOS 14/15

## 1.0.1

- Uniform dashboard background: the sidebar is no longer translucent
- Refreshed README screenshots

## 1.0.0

First public release.

- New app icon artwork across all four selectable styles
- Dock icons chosen in-app now match the size of other Dock icons
- Icon pipeline simplified to pre-rendered PNGs; generation scripts removed

## 0.1.1

- Settings merged into the dashboard with a sectioned sidebar
- Five menu bar icon styles with status colors and live previews
- Selectable app icon with four artworks
- Pinned always-on-top stats window
- Apple's own health rating and condition shown alongside measured values
- Manufacture date decoding fixed and shown with battery age
- Smooth sidebar animation, fixed-size dashboard, popover hover tooltips
- Deep links (battistics://dashboard/...), Dock icon reopen support
- Many correctness fixes from a full code review

## 0.1.0

Initial version.

- Menu bar popover with charge and health gauges, capacity, cycles,
  temperature, power, voltage and time estimates
- Customizable menu bar display: bat glyph with live fill, charge, health,
  time, temperature or power text, color rules for low, high and charging
- Dashboard with Overview, History, Details, Peripherals and Energy views
- Charge, power, temperature and health history with day, week, month and
  year charts plus on-battery, charging and fully-charged time totals
- Event driven engine: zero polling while idle, sensors sampled only while
  a window is visible, one coalesced background tick for power history
- Notifications: low battery, drop reminders, charge limit, fully charged,
  high temperature, long time on battery, health decline
- Peripheral battery levels for connected keyboards, mice, trackpads and
  headphones
- Energy view showing the busiest processes, sampled only while open
- CSV export and import of the full history, SQLite storage with automatic
  compaction
- Liquid Glass UI on macOS 26 with native material fallback on macOS 14/15
- Sparkle auto-updates. No analytics, no other network traffic
