# Physical remote-delivery and energy validation

The short iPhone 17 transport trial in [nearby-handoff.md](nearby-handoff.md#validation) passed. It used synthetic status and an ephemeral key, so it does not establish Production CloudKit provisioning, the complete background Live Activity path or sustained energy use. A CloudKit trial requires a verified same-account pair; USB trust and the diagnostic fixture do not establish that requirement.

## Prerequisites

- An iPhone and Mac signed in to the **same Apple Account**, with iCloud available to both apps. Signing into or switching accounts is an owner action, not a test-automation step.
- Both installed builds point to the **same CloudKit environment**. A Development trial is useful but does not establish Production schema/signing/push health. A Production trial needs correctly provisioned builds with Production CloudKit and APNs entitlements; merely selecting Release is insufficient.
- Record the commit, app versions/builds, OS versions, environment, permission states, Background App Refresh, Low Power Mode and network/radio conditions. Keep the Mac's network configuration unchanged.
- Enable sharing on the Mac, establish a fresh real reading on the iPhone, and start a timed **display-may-sleep** Keep Awake session long enough for the trial. Avoid closed-lid/helper changes during this delivery test. Verify that a Live Activity already exists before locking. Do not force-quit either app.
- For a trace-enabled Debug build, launch both apps once with `-remote-delivery-trace`, then detach the debugger and stop the UI test runner. Filter device/Mac unified logs to subsystem `com.doguyilmaz.Battistics.Remote`, category `DeliveryTrial`. Console capture is permitted; do not attach a debugger or foreground the phone to obtain fresh readings during the observation window. Check beforehand that the trace is present. Release builds emit no trial trace.

The opt-in trace records `cloudPublished`, `cloudReceived`, `nearbyReceived`, `applied`, `activityCreated` and `activitySubmitted`, with sample time, observation time, revision, hashed Mac identifier and phone app state (`2` is background, `-1` is not applicable). It logs no keys, network names, device names, command arguments or battery payload. Hashes are correlation identifiers, not anonymous aggregate telemetry; retain logs locally and redact before sharing. No extra timer or background entitlement is added.

## CloudKit → Live Activity, 60–120 minutes

1. On the **phone only**, disable Bluetooth and Local Network access for Battistics Remote in app settings. Leave its internet connection, notifications and Live Activities enabled. Open Remote once, confirm an iCloud reading and the session's Live Activity, then return to the Lock Screen. On this iPhone 17, use Wi-Fi or the existing Hotspot; there is no cellular connection.
2. Record the UTC start. Leave the app backgrounded for 60–120 minutes. Do not pull to refresh, run foreground automation or force a background task to simulate natural silent-push delivery.
3. Confirm that the Mac continues publishing and collect the corresponding trace milestones. At predefined checkpoints, inspect the Lock Screen without opening the app; record a photo/video and the displayed last-update time. A countdown advancing by itself does **not** prove new data arrived.
4. At the end, record the UTC cutoff **before** opening Remote. Export logs and correlate the same Mac hash, revision and sample time. Count only receipts and ActivityKit submissions before the cutoff. Reopening the app and then seeing current data is a foreground-recovery result.

Interpret each stage separately: a missing Mac publication points to Mac/CloudKit work; a publication without a phone receipt points to background delivery/fetch; a receipt without `applied` may be rejected older data; an applied reading without an activity submission points to reconciliation/authorization or unchanged content. A submitted update is an ActivityKit API milestone, **not proof that iOS displayed it**: compare the visible Lock Screen separately. Report callback counts, maximum sample age, gaps and foreground/background state rather than inventing a background-latency SLA. Apple may throttle silent pushes even when publication continues.

## Bluetooth-assisted background, 2–4 hours

Restore app Bluetooth permission on both devices and establish a fresh nearby connection while foregrounded. Keep the phone on its available internet connection, then lock it and observe for 2–4 hours using the same cutoff and correlation procedure. A `nearbyReceived` trace distinguishes the local path from CloudKit but does not itself distinguish LAN from BLE. Since the app closes LAN when backgrounded, stable background nearby receipts are BLE evidence; verify that the recorded app state remains background. Do not count the first foreground/inactive transition as BLE-only proof.

Separately repeat range loss/return and app Bluetooth-deny/allow recovery on the phone, while the Mac network stays fixed. Check that stale data is not marked fresh, commands keep one identity across fallback, and a returned connection resumes updates. Test OS termination/restoration separately from a user force-quit; they have different background behavior. Keep the trial below eight hours when measuring continuity of one Live Activity, because iOS imposes its own duration limit.

## Energy comparison, unplugged

USB charging invalidates a battery-drain measurement. Use the same phone unplugged, comparable starting charge/temperature, screen locked, no debugger or foreground test runner, the same Mac workload/session and the same notifications/network conditions.

Compare equal 2–4 hour windows: **A** uses CloudKit with nearby app permissions disabled; **B** enables nearby Bluetooth with the Mac in range. Keep global radio conditions otherwise the same; disabling Bluetooth globally would also change unrelated device traffic. Repeat both conditions, reversing their order (for example A/B then B/A). Use the same trace setting in both, and corroborate an uninstrumented run because diagnostic logging also consumes energy.

Record start/end charge, elapsed time, thermal conditions and iOS Settings › Battery app/background usage. Battery percentage has coarse resolution and other apps affect it; one short run or a one-point difference does not establish improvement or regression. Use Instruments Energy/Power measurements in a separate profiling session for attribution, and label that session as instrumented. Set an energy acceptance threshold only after repeatable baseline measurements; do not claim a fixed battery saving without them.

## Record the outcome

Keep a run record with setup, timestamped evidence, callback gaps, visible ActivityKit behavior, permission/range transitions, energy conditions and failures. Store raw logs under ignored `.build/` paths. Update the release validation notes only for completed runs. Required open cases remain Production trust bootstrap, natural background CloudKit/Live Activity delivery, long BLE/restoration recovery and energy impact.

References: [Apple local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), [background push constraints](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app), [Live Activity constraints](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).
