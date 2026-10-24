<p align="center">
  <img src="Sources/BattisticsApp/Resources/AppIcons/original.png" width="128" alt="Battistics">
</p>

<h1 align="center">Battistics</h1>

<p align="center">Battery statistics for the Mac. Free, open source, native.<br>
macOS 14+ · Apple Silicon</p>

![Dashboard](docs/overview.png)

<p align="center">
  <img src="docs/popover.png" width="252" alt="Menu bar popover">
  <img src="docs/appearance.png" width="560" alt="Appearance settings">
</p>

## Features

- Charge, health, capacity, cycles, temperature, power, voltage and time estimates at a glance
- History charts for charge, power, temperature and health across day, week, month and year
- Customizable menu bar icon: five styles, status colors, optional text, selectable app icon
- Notifications for low battery, full charge, charge limit, high temperature and health decline
- Battery levels of connected keyboards, mice, trackpads and headphones
- Energy view showing the busiest apps, sampled only while open
- Keep Awake for 15 minutes to 12 hours or until turned off, including with the lid closed, with ready-made profiles
- Optional stop at a battery level or under heat, low-battery and unplug warnings
- Keep Awake for terminal commands and AI tasks through a bundled CLI and local MCP server
- Battistics Remote for iPhone: battery, connection and Keep Awake through your iCloud
- A short tour and searchable help, with optional on-device answers on macOS 26
- CSV export and import of the full history
- English and Turkish

## Keep Awake modes

| | Keep the display on | Let the display sleep | Stay awake with the lid closed |
|---|---|---|---|
| Display | Stays lit | Sleeps on its timer | Sleeps on its timer; the built-in one is off while shut |
| Closing the lid | Mac sleeps¹ | Mac sleeps¹ | Mac keeps running |
| Screen locks² | When you lock it or close the lid | When the display sleeps | When the display sleeps or the lid closes |
| Apple menu › Sleep | Works | Works | Ignored until the session ends |
| Battery use | Highest, the screen stays on | Low | Low, but a closed bag traps heat |
| Setup | None | None | Power helper, approved once in Login Items |
| Equivalent | `caffeinate -d` | `caffeinate -i` | `caffeinate -i` + `pmset disablesleep 1` |

All three work on battery or adapter and end on their timer even if Battistics is suspended. Closed-lid mode only borrows the system sleep setting: if Battistics quits or crashes the helper restores it within 45 seconds, a change made elsewhere is left alone, and a session that ends with the lid shut lets the Mac sleep.

¹ Unless it is in clamshell mode, with an external display and power connected.
² Only if Lock Screen settings require a password after the display turns off.

### Protection

In **Power › Session Protection**, or **Stop on Low Battery** in the menu bar's
Keep Awake menu, Keep Awake can end at 5–50% charge on battery. It is off by
default and only ends the session; it never shuts the Mac down. Warnings start
at 20%. **Thermal Care** warns under heavy thermal pressure and can stop the
session. Fan speeds are not changed. Details: [session protection](docs/session-protection.md).

### Terminal and AI tasks

Turn on **Power › Local automation**, then:

```sh
battistics run --name Build -- swift build
```

Keep Awake lasts as long as the command, 12 hours at most, and never kills it.
AI clients use the bundled MCP server to start and stop a named task. See the
[command contract](docs/developer-sessions.md) and [MCP setup](docs/mcp.md).

### iPhone

Battistics Remote shows the Mac's battery and its last day, how long it lasts,
its connection, lid and heat, and starts or stops Keep Awake, even with the lid
closed in a bag. Widgets and a Lock Screen countdown come with it. Turn on
**iPhone** in Battistics; any iPhone on the same Apple ID finds the Mac through
your private iCloud, with nothing to pair or install. With no Wi‑Fi, a Mac set
to join hotspots automatically uses the iPhone's hotspot. See
[remote companion](docs/remote.md).

## Light by design

Uses power-change notifications with a low-frequency battery refresh fallback. Detailed views and optional power-history recording add work while enabled. Background activity is minimized, but CPU and energy use vary with settings and hardware; no fixed 0.0% CPU guarantee is made.

## Install

```sh
brew install --cask doguyilmaz/tap/battistics
```

Or download the DMG from [Releases](https://github.com/doguyilmaz/battistics/releases) and drag Battistics to Applications.

Either way updates arrive in-app: Battistics updates itself, so Homebrew is told to leave it alone once installed.

## Build

```sh
brew install xcodegen
make run    # debug build and launch
make test   # unit tests
```

Run `make gen` and open `Battistics.xcodeproj` to work in Xcode.
The MCP dependency requires Swift 6.1 or later. After a debug build,
`scripts/test-cli.py`, `scripts/test-mcp-stdio.py` and
`scripts/test-automation.py` (`--tour`, `--remote`) run the integration checks.
The iPhone app is the `BattisticsPhone` scheme.

## Privacy

Runs entirely on your Mac. The only network request is the optional update
check. Sharing with your iPhone is off by default; when on, the Mac's status
goes through your private iCloud, encrypted, and no port is opened.

## License

MIT
