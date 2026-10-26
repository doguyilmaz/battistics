# Changelog

## Unreleased

- Battistics Remote for iPhone: battery and its last day, time left,
  connection, lid, heat and Keep Awake for the Macs on your Apple Account, with
  start and stop, push alerts, Siri shortcuts, widgets and a Lock Screen
  countdown. Off by default on the Mac; everything goes through your private
  iCloud, with nothing to pair.
- The Keep Awake card shows the connection, a closed lid and, on battery,
  when the charge will not last the session.
- Optional Keep Awake stop at a battery level, also in the menu bar's Keep
  Awake menu, with advance warnings; off by default. Optional stop under heavy
  thermal pressure; fan speeds are not changed.
- Optional warning when the adapter is unplugged during Keep Awake.
- Picking a duration during a session applies it from that moment.
- Keep Awake for terminal commands with `battistics run`, and for AI tasks
  through a bundled, opt-in local MCP server.
- AI Focus, Long Build, Overnight and Presentation profiles, and a session card
  showing what started Keep Awake and why the last one ended.
- An eight-step tour on first launch, replayable from Help, and searchable help
  in English and Turkish with optional on-device answers on macOS 26.
- Power shows "Sleep is turned off" with Allow Sleep when macOS's sleep
  override outlived a closed-lid session, for example after a power loss.
- The live readings in Overview and the popover keep every row, with a dash
  for a value macOS has not reported, so the cards no longer change height.
- "Still on Battery" is sent once per unplug, also across a relaunch.
- Battistics Remote can remove a Mac that no longer answers, and tells you
  when a command from a widget, the Lock Screen or Control Center was refused.
- Power is now three panes: Keep Awake, Power and, under Developer,
  Automation. Explanations moved behind info buttons, thresholds sit next to
  their switch, and every pane fits the window without scrolling.
- Add Time extends a running Keep Awake from the Mac, the iPhone, the Lock
  Screen, the large widget or Shortcuts.
- The Mac sends its alerts to the iPhone through iCloud, so they arrive at
  once, also while Battistics Remote is closed.
- The Mac answers the iPhone promptly while its window is closed.
- Battistics Remote reminds you five minutes before Keep Awake ends, with a
  button to add 30 minutes, and warns when a session runs hot.
- An All Macs widget, Get Mac Battery Level for Shortcuts, and Siri starts
  Keep Awake in any mode, also until turned off. Each Shortcuts action can
  name the Mac it acts on, and Open Mac opens one in the app, also by name
  from Siri. The All Macs widget also fits the Lock Screen. On the Home
  Screen tapping a Mac in it opens that Mac, and every other widget and the
  Live Activity open the Mac they show.
- Try a Sample Mac shows the iPhone app before a Mac is set up.
- Battistics Remote widgets move up a Smart Stack while Keep Awake runs or
  the battery runs low, and show a desktop Mac's network and heat.
- Alerts the Mac pushes name that Mac on the iPhone and group by Mac. The
  Keep Awake card names a profile or task, and a Mac running a newer
  Battistics asks you to update Battistics Remote instead of looking live.
- Switching a running session to closed-lid keeps the Mac awake while the
  power helper is set up.

## 1.4.1

- The popover's Keep Awake menu marks the duration and mode you picked. The
  choice was applied, but the menu kept marking the one it first opened with

## 1.4.0

- Closed-lid Keep Awake sets up its power helper itself. Turning it on
  installs the helper, starts once it is allowed in Login Items, and
  replaces a helper left running by an earlier version. When something is
  still missing, the message says what, not just "could not start"
- A closed-lid session that ends with the lid still shut lets the Mac sleep,
  as closing the lid normally would, instead of running until the battery
  is empty. The previous sleep setting is restored as before
- The detached window keeps the Overview, Low Power Mode, Keep Awake and
  settings buttons
- The dashboard sidebar's divider no longer runs through the window title
- On macOS 27, cards in the popover and dashboard use a plain background,
  since Liquid Glass nested in the popover changed their colors
- An update found in the background no longer opens its window behind
  other apps, where it could sit unnoticed for weeks. It shows in the menu
  bar panel and, when notifications are allowed, as a notification; either
  one opens it. Right after launch it still opens directly
- Turkish now covers the stat labels, gauge titles, section headers and
  their help, and the status line in the popover and Overview. They were
  translated but always drawn in English
- Helper crashes are detected in About. Their reports were looked up under
  the wrong name and in the wrong folder
- The high temperature notification threshold follows the temperature unit
  setting instead of always showing Celsius
- "Start at login" reflects changes made in System Settings
- One "Report a Problem…" replaces the separate issue and email buttons.
  It shows exactly what is added to the report and any recent crash file,
  and it is reachable from the popover's new settings menu and the Help
  menu, not only from the bottom of About
- The popover's gear button opens a menu with Settings, Check for Updates,
  Report a Problem, About and Quit. The footer is more compact, and the
  popover closes when one of its buttons opens a window
- Numbers follow the region's format, and durations and battery age are
  translated: Turkish shows "%85", "34,5°C", "7 sa 23 dk" and "3,8 yıl"
- Details' "Copy Report" is now "Copy Battery Summary", so "report" means
  only a problem report
- The dashboard sidebar is grouped as Battery, Controls, Settings and
  Help. Details opens from Overview instead of repeating it as its own
  pane; System is now Power, with the power helper in its own section;
  Appearance is now Menu Bar, and its theme and app icon moved to General,
  together with Updates from About
- Notifications, Energy, Power Flow and the History totals are translated
  into Turkish

## 1.3.1

- Power Flow is now enabled by default for new installations and can be
  disabled from General settings. Existing preferences are preserved.

## 1.3.0

- Battery health and capacity readings now handle macOS 27 data layouts and
  keep unavailable health values neutral instead of presenting a misleading
  result
- Menu bar percentage text can be shown inside every battery icon style, with
  fitted text that preserves each icon's shape and localized settings labels
- Dashboard windows stay visible across Dock policy changes, and dashboard
  links route back to the running app correctly
- Charging status updates use supported power notifications with an independent
  sensor fallback, including more reliable menu bar refreshes
- Keep Awake supports renewable display and closed-lid leases, notices when a
  sleep setting was changed externally, and bounds helper command work
- Peripheral battery entries clear on disconnect and keep the correct device
  identity across Bluetooth reconnects
- History retention, CSV import and asynchronous health updates are safer when
  a storage or observation step fails
- Energy now shows up to twenty processes, explains visible-only sampling and
  avoids creating offscreen rows until they are needed
- History charts reserve their space before data arrives, preventing layout
  jumps while a view loads
- Optional Power Flow in Energy and the popover shows external input,
  system load and battery charge or discharge separately
- Inconsistent readings can show a marked estimate with its formula;
  a valid reported reading replaces the estimate automatically
- Power Flow information and estimate popovers fit narrow windows and
  remain readable in Light appearance

## 1.2.1

- The Power Adapter section on Overview stays where it is. It used to
  appear and disappear with the cable, and each of its rows with whichever
  values macOS had filled in yet, so plugging in moved the page more than
  once. Unplugged it now reads as dashes, with a "Not connected" tag

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
