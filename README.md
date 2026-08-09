# Battistics

Battery statistics for the Mac. Free, open source, native.

Battistics (Battery + Statistics) lives in the menu bar and gives an
at-a-glance, deeply detailed picture of the battery: charge, health, real
capacity, cycles, temperature, power flow and history over time. Built for
Apple Silicon Macs with a hard rule: never burn the battery it measures.

## Features

- **Menu bar first.** A bat-eared battery glyph with live fill level, plus
  optional text: charge %, health %, time remaining, temperature, power or
  mAh. Color rules for low charge, high charge and charging, or pure
  monochrome that matches the menu bar.
- **Popover.** Charge and health ring gauges, capacity readout (current,
  maximum, original), cycles, temperature in C and F, wattage, voltage,
  amperage, time on battery and a 24 hour sparkline. Every stat has a plain
  language explanation behind the section help buttons.
- **Dashboard.** Overview, full technical details with a copyable report,
  history charts (charge, power, temperature, health) across day, week,
  month and year with time totals for on battery, charging and fully
  charged, battery levels of connected peripherals and an energy view of the
  busiest apps.
- **Notifications.** Low battery with repeat-drop reminders, charge limit
  (unplug at 80%), fully charged, high temperature, long time on battery and
  battery health decline. All configurable, all optional.
- **History you own.** Everything is stored locally in SQLite and exports to
  a documented CSV format. Import brings it back. Old samples compact
  automatically so the database stays small.

## Light by design

- Charge tracking is fully event driven through IOKit power notifications:
  zero polling, zero timers while idle. Idle CPU is 0.0%.
- Temperature, wattage and voltage are read only while a Battistics window
  is actually visible.
- Power history uses a single coalesced reading per minute (configurable or
  off), which costs microseconds.
- Energy sampling runs only while the Energy view is open.
- One process. No helpers, no daemons, no launch agents.

## Privacy

Battistics makes no network requests except the Sparkle update check, which
can be turned off. No analytics, no tracking, nothing leaves the Mac.

## Requirements

macOS 14 or later on Apple Silicon. On macOS 26 the interface uses Liquid
Glass; on macOS 14 and 15 it falls back to native materials.

## Install

Download the latest DMG from
[Releases](https://github.com/doguyilmaz/battistics/releases), drag
Battistics to Applications. Updates arrive in-app through Sparkle.

## Build from source

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
make gen      # generate Battistics.xcodeproj from project.yml
make run      # debug build and launch
make test     # core unit tests
make install  # release build into /Applications
```

To work in Xcode, open the generated project, not the folder:

```sh
xcodegen generate && open Battistics.xcodeproj
```

The `.xcodeproj` is generated from `project.yml` and never committed.

## Architecture

```
BattisticsCore/   Swift package, no UI imports, fully unit tested
  Battery/        IOKit smart battery reader, event driven power monitor
  History/        SQLite store, retention, CSV port, time totals math
  Alerts/         pure alert rule reducer
  Peripherals/    HID battery levels
  EnergyHogs/     per-process energy sampling
App/              SwiftUI app: menu bar scene, dashboard, settings
```

The core package carries all logic and the tests (`swift test` inside
`BattisticsCore/`). The app layer stays thin: it consumes core event streams
and renders.

## Roadmap

- iPhone and iPad battery monitoring
- Global keyboard shortcut for the popover
- Multiple device support
- A `batt` command line companion

## License

MIT. See [LICENSE](LICENSE).
