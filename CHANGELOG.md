# Changelog

## 1.2.0

- Install with `brew install --cask doguyilmaz/tap/battistics`; the DMG is
  still there, and updates arrive in-app whichever way you installed
- Report a bug from About, by issue or by email, prefilled with your version
  and Mac model. If Battistics or its helper crashed recently, the report
  macOS wrote is offered next to those buttons rather than left where you
  would have to know to look
- Temperature history is drawn on a scale a battery actually lives on. It
  shared the power chart's axis, which starts at zero, so a day between 27
  and 35 degrees was squeezed into the top of the chart
- Temperature history follows the unit set in Settings instead of always
  showing Celsius
- History charts no longer jump as a tab loads, and no longer draw over the
  controls above them

## 1.1.0

**Install this one by hand.** The app's internal identifier was misspelled.
Correcting it means macOS treats 1.1.0 as a different app, so it cannot
replace 1.0.2 in place. Charge and health history is kept; menu bar and
notification settings return to their defaults. Updates are automatic again
afterwards.

- Keep Awake: stop the Mac sleeping for 15 minutes to 12 hours or until
  turned off, with the display on, the display asleep, or the lid closed
- New System pane: Low Power Mode, Energy Mode and the display, system and
  disk sleep timers, readable and changeable, plus a link into Battery
  settings
- Optional helper that removes the password prompt from those changes
- Low Power Mode shows inside the charge ring and switches from the popover
- Quit a process from the Energy pane on hover
- Capacity no longer reports above 100%: a young battery really does measure
  above its nameplate, and macOS clamps it too
- "Battery health declined" compares a 30-day median instead of yesterday,
  so a reading that swings a few points a day stops triggering it
- Capacity history draws a 7-day trend through the daily readings
- Cycle count gets a gauge on Overview

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
