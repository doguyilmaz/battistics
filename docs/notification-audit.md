# Notification audit — 2026-11-13

The reported alerts could fire while the Mac and Keep Awake were working.
They were local timers based on the last status received by the iPhone,
not observations of user activity, sleep, or background-task completion.

## Resolved findings

| Finding | Implemented behavior |
| --- | --- |
| Missed silent pushes produced a passive note followed by an audible alarm. | Removed both speculative timers and the background-delivery cadence heuristic. Launch cleans up timers left by older versions. |
| One fresh reading rearmed the same missing-update warning. | Per-Mac persisted confirmation requires two successful reads of the same status, at least two minutes apart and at least 30 minutes old. Rearming requires ten minutes of advancing fresh readings. Failed reads cannot establish an outage or recovery. |
| Brief battery and thermal recoveries repeatedly notified. | Persisted episode latches require sustained recovery; battery readings also need a five-point margin or sustained external power. Local thermal warnings receive the same recovery delay. Stop protections remain immediate. |
| Unplugging and closing the lid could report the same Wi-Fi concern separately. | One network-risk warning per Keep Awake session. Runtime-estimate warnings are also once per session. |
| Routine task completion and healthy network transitions caused interruptions. | Manual/phone stops, completed terminal/AI work and Bag Ready transitions stay silent. Automatic task leases do not schedule five-minute reminders. Protection stops, sleep and timer expiry still notify. |
| An uncertain CloudKit save could create another event and push when retried. | Persist the latch and outbox together; retries reuse the event id and verify an already-saved matching record. Drop resolved and expired pending risks. |
| Failed subscription checks switched to local alerts even when pushes were still enabled. | Preserve the last accepted subscription policy on a transient check failure. |
| Turning notifications off depended on a later fetch to clear old timers. | Clear pending and delivered notifications immediately, and check the preference again after an asynchronous add. |
| A stale reading ended the Live Activity and labelled the Mac offline. | Preserve the known session as a stale activity and show freshness; only reported sleep, an ended session, removal, or the known deadline ends it. Widgets say “Status out of date”. |
| A queued missing-update alert could become obsolete during awaited activity work. | Recheck the newest reading immediately before delivery; fresh, sleeping, ended or missing Macs cannot receive that queued alert. |

The charge-target latch remains independent so each new charge can notify.
The changes add no user-input or CPU-idleness inference to Keep Awake.

## Validation

- `swift test`: **264 tests passed**, including the alert policy, persistence,
  uncertain-save retry, temporal recovery and existing sleep/protection tests.
- Hosted iOS tests on **iPhone 16e, iOS 18.6 Simulator**: **2 passed, 0 skipped**.
  These use the real notification center to verify known-deadline scheduling,
  absence of speculative timers, cleanup of legacy timers for forgotten Macs,
  immediate offline switch-off and suppression of obsolete queued alerts.
  ActivityKit is exercised with old telemetry and an explicit sleep report.
- iOS app, widget and notification extensions compiled successfully.
- macOS app, helper and command-line targets compiled successfully.
- Xcode static analysis completed successfully for both app schemes.
- English and Turkish strings validated; `git diff --check` passed.

## Deployment and limits

Both shipped apps are affected:

- **iOS app, widgets and notification extension:** remove speculative
  missing-update timers, confirm stale records per Mac, clear old reminders,
  respect switch-off immediately and preserve stale Live Activities.
- **macOS app:** persist alert repeat suppression and the retry outbox, keep
  normal task completion silent and delay thermal-warning rearming until
  recovery. Battery and thermal stop protections remain immediate.
- **Shared module:** both apps consume the updated alert policy. There is no
  CloudKit schema or remote-command protocol change, so the apps can roll out
  independently. Ship both releases for the complete fix; the reported false
  local timer notification is fixed by the iOS release.

These changes have not been released or installed over the Mac's running
production app. Version numbers and release tags are unchanged. A physical
iPhone and the production CloudKit delivery path were not exercised in this
pass; CloudKit failure and retry behavior is covered with controlled SDK
operation callbacks.

An iPhone that cannot run a successful fetch cannot issue a newly confirmed
missing-update alert. It instead retains the last known status with its
freshness indication. This avoids presenting delayed iOS delivery as proof
that a background job stopped; Mac-side battery and thermal protections
continue independently of phone delivery.
