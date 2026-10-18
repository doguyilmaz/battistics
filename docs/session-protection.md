# Session protection

Keep Awake can warn or end a session at user-selected limits.
“Stop at X%” ends the Battistics session. It does not issue shutdown or force
system sleep: macOS resumes its normal behavior, including immediate sleep when
the lid is closed. Battery depletion, sleep, and an actual shutdown cannot be
distinguished from a user's anecdote alone.

## Behavior

- Automatic battery stopping is opt-in, with a 10% initial selection and 5–50%
  range. External power exempts this rule even when the battery is not charging.
- Warnings default to 20%, with a 10–80% range. If stopping is enabled, the
  warning threshold is at least five percentage points higher. Warnings can be
  disabled without disabling automatic stopping.
- Battery rules consume the existing sensor pipeline, including its 15-second
  fallback, rather than depending on a visible view or history recording.
- The same policy checks conditions before starting and again after helper
  authorization. A skipped warning level still triggers the enabled stop.
- Missing, invalid, and absent-battery readings do not count as zero charge.
- Serious/critical system thermal pressure always warns during a session;
  automatic stopping is opt-in and works on both battery and adapter.
- Ending a protected session follows the existing assertion and helper-lease
  cleanup path. The stop reason stays visible. It never restarts automatically.
- A nonactivating notice works without notification permission. When the screen
  is locked, it waits for unlock. macOS notifications are also requested.
- Protections are best effort while the app runs. They cannot guarantee a
  warning before abrupt power loss or timely action if the process is suspended.

## Fan control

Direct fan overrides need hardware-specific support and a separate recovery
design. They are technically possible: [Macs Fan Control](https://crystalidea.com/macs-fan-control/faq)
uses low-level hardware access with administrator permission. This version only
reads macOS thermal signals and does not write fan settings. Apple's
[fan guidance](https://support.apple.com/en-us/101576) explains ventilation and
automatic cooling.

## Verification

`swift test` covers threshold crossing, warning deduplication/rearming, sudden
charge drops, AC transitions, invalid/missing readings, opt-in defaults,
configuration changes, thermal recovery, and threshold bounds alongside the
existing assertion/lease tests. `make build` compiles the macOS app and helper.
