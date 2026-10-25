# Session protection and help

“Stop at X%” ends the Keep Awake session; it never shuts the Mac down or forces
sleep. macOS then behaves normally, which with the lid closed means sleeping
right away.

## Behavior

- The battery stop is opt-in: 10% preselected, 5–50%, on battery only.
- Low-battery warnings default to 20% (10–80%) and stay at least five points
  above the stop. They can be turned off on their own.
- Readings come from the app's normal sensor pipeline, so protection works with
  every window closed and history off. Missing or invalid readings never count
  as an empty battery; a sudden drop past the warning still stops.
- Conditions are checked before a session starts and again after helper
  authorization.
- Serious or critical thermal pressure always warns during a session; stopping
  on it is opt-in and works on either power source.
- The adapter-disconnect warning is opt-in. Only an observed adapter-to-battery
  change during a session counts; unplugging never stops the session.
- A stop keeps its reason on screen and never restarts by itself. The in-app
  notice works without notification permission and waits for unlock.
- All of this is best effort while the app runs; it cannot warn before an abrupt
  power loss.

## Help

The eight-step tour visits Overview, Power (Keep Awake, profiles, protection,
automation), Notifications, History and Help, never changes a setting, and can
be replayed from Help.

Built-in answers work offline on macOS 14 and later. On macOS 26 with Apple
Intelligence, the assistant picks one of up to three matching built-in articles
by number and the app shows that article's reviewed text; model-written prose
is never displayed. No tools, setting changes, cloud fallback or stored
conversations.

## Scope

Fan speeds are not changed. Tools such as [Macs Fan Control](https://crystalidea.com/macs-fan-control/faq)
write fan settings with administrator rights and per-model support; Battistics
only reads macOS's thermal signal. Apple's [fan guidance](https://support.apple.com/en-us/101576)
covers ventilation.

## Release checks on a signed app

1. Walk the tour in both languages without changing power settings.
2. Set a battery stop above the current charge while unplugged; the session
   ends and cannot restart until power is connected. Repeat in closed-lid mode
   with the lid open first and confirm the helper restores sleep.
3. Get a warning with notifications denied, and across a lock and unlock.
4. Check protection with every window closed and history sampling off.
5. Check the assistant with Apple Intelligence off, the model downloading, an
   unsupported language and ready.

Use simulated readings for depletion and heat; never drain or overheat a Mac
on purpose.
