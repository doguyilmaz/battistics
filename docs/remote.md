# Remote companion

Battistics Remote is a one-screen iPhone app for a Mac that may be closed in a
bag: is it awake, online, how long does its battery last, and start or stop
Keep Awake.

## How it connects

- **Off by default.** Battistics › iPhone turns on a listener bound only to the
  Mac's Tailscale address (100.64.0.0/10), port 47616. Nothing listens on the
  LAN or the internet. Without Tailscale there is nothing to pair with.
- **Pairing.** The Mac shows a QR code for ten minutes. It carries the Mac's
  name, Tailscale address, port and a random 256-bit token. The phone keeps the
  pairing in its Keychain (this device only); the Mac keeps only the token's
  SHA-256 hash and compares in constant time. Removing the iPhone on the Mac
  revokes it. A link with a non-Tailscale address shows a warning.
- **Protocol.** One newline-terminated JSON request and reply per TCP
  connection, 16 KB at most. Peers outside the tailnet are dropped on accept,
  each peer gets two connections and three seconds to send its request, and
  five failed tokens from one address lock it out for a minute. Tailscale
  encrypts the link.
- **Same rules.** Phone sessions are finite (15 minutes to 12 hours), never
  replace a running session, follow battery and heat protection, and need a
  separate switch plus an installed helper for closed-lid mode. The phone can
  stop any session; settings cannot be changed remotely.

The contract lives in `Sources/BattisticsRemote`, shared by both apps.

## What the phone shows

Battery and time left or to full, health; Keep Awake with a countdown, origin
(Mac, profile, terminal, AI task, iPhone) and why the last session ended; the
Mac's connection (Wi‑Fi, hotspot, Ethernet, offline), lid, heat and battery
stop. When battery will not last a timed session, it says so. When the Mac
stops answering, the last reading stays visible, dimmed, with hotspot tips.

The Mac reads all of this without root: `NWPathMonitor` (an iPhone hotspot is an
expensive path, so no Location permission), `AppleClamshellState` from the
power manager, and the existing battery reader.

## Notifications

Local notifications from background refresh: no server and no cost. They fire
when a session ends (unless the phone stopped it), the battery crosses its
warning level, the battery will not last the session, or a Mac stops answering
mid-session. iOS schedules background refresh, so alerts can be late.

Siri and Shortcuts get Keep Mac Awake, Let Mac Sleep and Check Mac; all require
an unlocked iPhone.

Widgets (Home Screen and Lock Screen) show the selected Mac's battery and Keep
Awake state from the app's last reading, shared through an App Group. A timed
session also gets a Lock Screen and Dynamic Island countdown that ends when the
app sees the session end.

## Hotspot

iOS gives apps no way to turn Personal Hotspot on, and its settings page has no
public link. The Mac can join it by itself: Wi‑Fi settings › Ask to join
hotspots › Automatic. Keep Awake keeps the Mac, and so the connection, awake.
The iPhone pane on the Mac and the phone's settings both explain this.

## Not built yet

- Joining a remembered iPhone hotspot from the Mac when it goes offline during
  a session (CoreWLAN; needs Location permission and a spike on macOS 14/26).
- Bluetooth LE between phone and Mac in the same bag, for status and "join the
  hotspot" with no network at all.
- CloudKit push for prompt alerts, which needs an iCloud container on both apps.
- Device builds need the team set in `project.yml`; the scheme builds for the
  Simulator as is.

## Developing

`BATTISTICS_REMOTE_SERVE=/tmp/pair.txt python3 scripts/test-automation.py --remote`
serves the protocol on loopback from an isolated test app and writes a pairing
link; open it in the Simulator, which shares the Mac's loopback.
