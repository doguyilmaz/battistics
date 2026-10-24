# Remote companion

Battistics Remote is a one-screen iPhone app for a Mac that may be closed in a
bag: is it awake, online, how long does its battery last, and start or stop
Keep Awake.

## How it connects

Through the user's private iCloud database (CloudKit). There is no server, no
port on the Mac, no pairing and nothing to install: the iPhone and the Mac only
need the same Apple ID.

- **Off by default.** Battistics › iPhone › Show this Mac in Battistics Remote
  starts sharing. Turning it off deletes the Mac's record, so it disappears
  from the phone.
- **Records.** One `Remote` zone holds a `MacStatus` record per Mac and short-
  lived `Command` records from phones. Payloads live in CloudKit's encrypted
  fields, keyed through the account's iCloud Keychain.
- **Status.** The Mac writes when something changes (session, battery, heat,
  network, lid) and at least every ten minutes as a heartbeat. A reading older
  than twenty minutes shows the Mac as not answering.
- **Commands.** The phone writes a command; the zone subscription pushes the
  Mac, which runs it, deletes it, and records the outcome in its status. The
  phone watches for that outcome for about 25 seconds, then deletes the command
  so a late Mac never acts on it. The Mac also drops commands older than two
  minutes and fetches every five minutes in case a push was lost.
- **Same rules.** Phone sessions are finite (15 minutes to 12 hours), never
  replace a running session, follow battery and heat protection, and need a
  separate switch plus an installed helper for closed-lid mode. The phone can
  stop any session; settings cannot be changed remotely.

The contract and CloudKit code live in `Sources/BattisticsRemote`, shared by
both apps.

## What the phone shows

Battery and time left or to full, health and the last 24 hours of charge; Keep
Awake with a countdown, origin (Mac, profile, terminal, AI task, iPhone) and
why the last session ended; the Mac's connection (Wi‑Fi, hotspot, Ethernet,
offline), lid, heat and battery stop. When the battery will not last a timed
session, it says so.

## Notifications

iCloud's silent push wakes the phone when a Mac's record changes, so alerts
arrive without a server: a session ends (unless the phone stopped it), the
battery crosses its warning level or will not last the session, or a Mac stops
answering mid-session. Background refresh is the fallback.

Siri and Shortcuts get Keep Mac Awake, Let Mac Sleep and Check Mac; all require
an unlocked iPhone. Widgets and a Lock Screen and Dynamic Island countdown read
the app's last reading through an App Group.

## Hotspot

iOS gives apps no way to turn Personal Hotspot on. The Mac can join it by
itself: Wi‑Fi settings › Ask to join hotspots › Automatic. Keep Awake keeps the
Mac, and so the connection, awake.

## Signing

iCloud needs a provisioning profile, so ad-hoc builds (`make build`, CI) leave
the entitlements out and the iPhone pane says the copy is not signed for iCloud.

- iPhone: team `5MYT4VYJFC` in `project.yml`; Xcode manages the profile.
- Mac: the `com.doguyilmaz.Battistics` App ID needs iCloud with the
  `iCloud.com.doguyilmaz.Battistics` container and Push Notifications enabled
  (Xcode › Signing & Capabilities, or the developer portal). Then
  `make run-icloud` builds a signed debug copy. Releases additionally need a
  Developer ID profile with the same capabilities embedded and the app
  re-signed with `Sources/BattisticsApp/Support/Battistics.entitlements`;
  `scripts/sign-app.sh` does not do that yet.

## Not built yet

- A direct connection when Mac and phone share a network (Bonjour), for
  instant updates on a hotspot.
- Joining a remembered iPhone hotspot from the Mac when it goes offline during
  a session (CoreWLAN; needs Location permission).
