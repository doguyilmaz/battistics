# Remote companion (plan)

Status: proposal. Nothing here is built yet, and whether it ships is undecided.

Goal: a closed Mac in a bag stays reachable and online, and an iPhone can see
at a glance whether it is awake, online, how long its battery lasts, and start
or stop Keep Awake.

## Shape

- **iPhone app.** One SwiftUI screen: Mac name, battery and charging, Keep
  Awake state and time left, a large Start/Stop, duration chips and mode. App
  Intents give Siri and Shortcuts for free. Same repo, separate target.
- **Mac side.** A "Remote access" setting, off by default. It listens only on
  the Tailscale interface (100.64.0.0/10 and the tailnet IPv6 range), never on
  the LAN or the internet.
- **Pairing.** A one-time QR code shown on the Mac; both sides keep the key in
  the Keychain. Tailscale encrypts the link; the pairing key keeps other
  devices and users on the same tailnet out. Unpairing revokes the key.
- **Same rules.** A remote session follows the ownership, time limit and
  battery/thermal protections that MCP and the CLI already use. Closed-lid mode
  needs its own permission, as for automation.
- **One contract.** The request and status types live in a small shared module
  with no IOKit or AppKit, used by the Mac app and the iPhone app.

## What the phone shows

Status beyond on/off, all read on the Mac without root:

- **Reachable / last seen.** When the Mac stops answering, show how long ago it
  last did instead of a stale "on".
- **Internet.** `NWPathMonitor` on the Mac: online or offline, and whether the
  path is expensive, which is how macOS marks an iPhone hotspot. Shown as
  Wi-Fi, iPhone hotspot or offline, with no Location permission needed.
- **Lid.** `AppleClamshellState` from `IOPMrootDomain`, readable without root.
- **Will the battery last?** Charge, drain and macOS's time remaining against
  the session's time left: "Battery lasts about 1 h 50 min; the session ends in
  3 h" is the warning that matters most in a bag.
- **Heat.** System thermal state, the same signal the thermal stop uses.
- **Why it stopped.** The last stop reason: timer, battery, heat, user, client.

## Hotspot

- **Not possible:** iOS gives apps no way to turn Personal Hotspot on or off,
  and a deep link to its settings page uses private URLs that App Review
  rejects. The phone can only ask the user to turn it on.
- **Built in on the Mac:** with Wi-Fi settings › Ask to join hotspots set to
  Automatic, the Mac joins the iPhone's hotspot by itself when no known Wi-Fi
  is in range. Keep Awake keeps the Mac awake, so the connection holds. Once
  the Mac is on the iPhone's network, Tailscale connects the two directly, even
  with the lid closed in a bag.
- **What Battistics adds:**
  - The session card shows Wi-Fi, iPhone hotspot or offline; the phone shows
    the same. When Ask to join hotspots is not Automatic, show how to set it.
  - Optional, opt-in: when the Mac goes offline during a session, join the
    remembered iPhone hotspot through CoreWLAN without waiting for macOS. This
    needs Location permission for network names; verify in a spike that
    `CWInterface.associate(to:password:)` works without admin rights on
    macOS 14 and 26.
- **Offline gap:** when the Mac has no internet, the phone cannot reach it over
  Tailscale to tell it anything. The Mac must act on its own (rule above), or
  a nearby channel is needed (see Later).

## Phases

1. **Mac only, no network exposure.** Connectivity, lid, battery-vs-session
   runtime and hotspot readiness in the session card. Useful alone; also the
   data the phone will show.
2. **Remote over Tailscale.** Listener, pairing, shared contract module,
   iPhone single screen, App Intents.
3. **Hotspot autopilot.** The opt-in CoreWLAN join after the spike.

## Later, undecided

- **Bluetooth LE when nearby.** iPhone and Mac in the same bag can talk over
  BLE with no network at all: status, plus "join the hotspot now". Messages
  signed with the pairing key. Worth a spike after phase 2.
- **Push without a server.** The Mac writes its status to the user's private
  CloudKit database, and a subscription pushes it to the phone: low battery or
  offline alerts while the app is closed. Needs an iCloud container on both
  apps.
- **Live Activity / widget** for the running session.

## Security

- Off by default; listener bound to Tailscale addresses only; pairing key per
  phone, revocable; every request authenticated with it.
- No shell execution, no setting changes beyond starting and stopping Keep
  Awake; protections cannot be turned off remotely.
- Remote access changes the README's "no network port" statement; update the
  Privacy section if this ships.

## Open decisions

- Ship at all, and whether phase 1 ships first on its own.
- App Store or TestFlight only for the iPhone app.
- Whether CloudKit (push, last seen) is worth an iCloud entitlement.
