# Session protection and guided help

This iteration focuses on understandable Keep Awake limits and discoverability.
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

## Help

The tour visits Overview, Power, Notifications, History, and Help, highlights the
current pane, supports Back/Next/Skip, and never enables settings. Finishing or
skipping persists locally; Help can replay it.

Built-in help is available offline on macOS 14+. The optional assistant checks
macOS 26+, model readiness, Apple Intelligence eligibility, and app-language
support. It receives only a bounded question and up to three relevant built-in
articles. Guided generation returns only an article number, validated against
the supplied candidates. The app displays that article's reviewed localized
answer; model-authored prose is never shown. This avoids invented functionality
observed during Turkish free-form generation testing. Each question creates a
fresh session with bounded output; no tools, settings writes, cloud fallback,
or persisted conversation are provided.
Cancellation and unavailable/error states return the user to the same guide.

## Deliberate scope boundaries

Direct fan overrides need hardware-specific support and a separate recovery
design. They are technically possible: [Macs Fan Control](https://crystalidea.com/macs-fan-control/faq)
uses low-level hardware access with administrator permission. This version only
reads macOS thermal signals and does not write fan settings. Apple's
[fan guidance](https://support.apple.com/en-us/101576) explains ventilation and
automatic cooling.

The assistant uses Apple's [Foundation Models framework](https://developer.apple.com/documentation/foundationmodels)
without raising the app's macOS 14 deployment target.

The [local MCP integration](mcp.md) owns bounded, named work sessions, releases
them on explicit completion or client loss, requires local opt-in, and preserves
the user's battery/thermal rules. Arbitrary shell execution, fan overrides, and
unrestricted privileged power settings remain outside its scope.

## Verification

`swift test` covers threshold crossing, warning deduplication/rearming, sudden
charge drops, AC transitions, invalid/missing readings, opt-in defaults,
configuration changes, thermal recovery, and threshold bounds alongside the
existing assertion/lease tests. `make build` compiles the macOS app and helper.

Development verification for this change: 181 core and MCP tests passed; the app,
helper, and MCP executable built with Xcode 26.6 targeting macOS 14. English/Turkish help, protection,
and dashboard-tour views were rendered in an isolated AppKit harness. Live
on-device article selection and cancellation were exercised in both languages.
Foundation Models is weak-linked for older macOS versions. The signed helper's
physical closed-lid flow and lock-screen delivery still need the release checks
below; rendering views does not exercise those system behaviors.
MCP handshake/discovery/error/EOF checks and the isolated app lifecycle harness
also passed; see [MCP verification](mcp.md#verification).

Manual release checks on a signed app:

1. On first launch, walk all five tour steps; verify Back, Skip, Done, replay,
   and both languages without changing any power settings.
2. Enable a battery stop above the current charge while unplugged. Confirm the
   session ends and cannot restart until conditions permit it. Repeat after
   enabling closed-lid mode, checking helper restoration with the lid open first.
3. Verify a warning with notifications denied, then during screen lock/unlock.
   Connect power and confirm the battery warning clears and can rearm on unplug.
4. Check protection with all windows closed and history sampling disabled.
5. Check the assistant with Apple Intelligence disabled, model downloading,
   unsupported language, and ready states; ask a guide-related question and
   cancel another. Verify the selected answer matches the displayed source.

Use simulated readings for depletion and thermal tests; do not deliberately
drain or overheat a development Mac.

Adapter-disconnect warnings are optional and off by default. During an active
session, an observed adapter-to-battery transition produces a notification and
an in-app notice. Starting on battery or losing sensor readings does not invent
a transition. Reconnecting rearms the warning. Battery/thermal stops take
priority; unplugging alone does not stop the session.
