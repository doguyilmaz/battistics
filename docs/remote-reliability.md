# Remote reliability without an additional service

Assessment: 2026-11-15. This describes the implementation in PR #57 and evaluates further work against Apple documentation. It does not establish the cause of the previously reported daytime incident: there is no matching iPhone log from that incident.

Follow-up: [LAN/BLE communication and automatic handoff](nearby-handoff.md) are now implemented on a separate branch. The nearby section below records the assessment that preceded implementation; its physical-device validation requirements still apply. The new transport code does not migrate to CKSyncEngine or add an ActivityKit push provider.

## Decision

Keep private CloudKit as the shared source of Mac state and the command mailbox. PR #57 improves recovery and makes the existing delivery stages observable. The follow-up adds cooperating nearby paths while preserving access across different networks without operating a service or distributing provider credentials.

Background delivery is a separate constraint. Apple's [background notification documentation](https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app) says delivery can be deferred and coalesced. More Mac writes cannot guarantee more iPhone execution time. A [background task's earliest begin date](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate) is a lower bound, not an execution appointment. These are not problems a different CloudKit read API can eliminate.

## What the code actually does

- `RemoteAccessModel` publishes significant changes and a heartbeat, currently 120 seconds during Keep Awake and 600 seconds otherwise. The Mac checks its command mailbox independently of phone execution. Current local Mac logs showed successful regular writes; this is evidence about the observed period, not the earlier incident.
- `RemoteCloud` registers `remote-zone` with `shouldSendContentAvailable`. The subscription covers both status and commands. [Record-zone subscriptions](https://developer.apple.com/documentation/cloudkit/ckrecordzonesubscription) notify the account's devices and can omit the device that originated a change. They are change hints, not a guaranteed event stream.
- `PhoneAppDelegate` handles the push by calling `MacStore.refreshAll`. Scheduled background refresh offers another opportunity. A foreground view also refreshes every ten seconds after its preceding fetch finishes.
- `MacStore` obtains the latest status, persists it, reconciles Live Activities and widgets, and finishes alert housekeeping before returning. The visible `remote-alerts` subscription also requests background delivery; it can offer another opportunity to fetch. The local missing-update reminders removed in iOS 1.0.1 never performed a fetch.
- `RemoteCommandExecutor` writes a command once and reads that Mac's record directly under its existing deadline. Commands remain separate from discovery and subscription maintenance.

## Implemented repairs and evidence

1. **Current values after discovery.** CloudKit query indexes [are updated asynchronously](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitWebServicesReference/QueryingRecords.html). Queries now discover IDs; one direct batch reads both discovered and saved IDs. Tests cover an indexed status three hours old, a known Mac omitted from the index, a deletion still indexed, unreadable payloads, and direct-read failure. An unsuccessful direct read preserves the previous phone state.
2. **Live Activity ordering and recovery.** Reconciliation includes lookup, creation, updates and ending in publication order. An old queued end cannot remove the subsequent session's activity. Only active/stale activities are reused. Simulator tests exercise stop/restart, replacement of an ended activity, and preserving a stale activity until explicit session end. This does not extend Apple's [eight-hour active duration](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities).
3. **Silent subscription recovery.** Previously, one successful save set an in-memory flag for the process lifetime. An accepted subscription is now checked during existing work after 30 minutes. Missing or incompatible settings trigger a repair; failures wait at least five minutes before retrying. Both intervals use a monotonic clock, and CloudKit retry-after is still honoured. Zone loss clears the cached state, and a late save for an earlier zone cannot confirm its successor. Controlled SDK-boundary tests cover loss, incompatible settings, healthy checks without rewriting, bounded failure recovery, and zone invalidation. Status reads and commands do not await maintenance; shared CloudKit back-off still applies. Maintenance creates no additional phone wake-up schedule.
4. **Accurate background results.** Push handling previously always reported `newData`, and scheduled refresh could report success after a failed read. The result now distinguishes changed, unchanged and failed/cancelled/expired reads. Apple explains that [background fetch outcomes inform future scheduling](https://developer.apple.com/videos/play/wwdc2020/10095). Returning accurate results is correct use of the API; no increase in background frequency is claimed. Simulator tests cover the delegate's no-data path and cancellation/deadline failures.
5. **Local evidence for a recurrence.** Unified-log categories `PhoneUpdates`, `CloudKit` and `LiveActivity` record APNs registration success/failure, push/background task arrival, operation completion/error, sample age and activity creation failure. Activity update completion is logged as submission, since ActivityKit content propagation can finish later. No token, Mac name, network name or payload is logged. An absence of phone callbacks during successful Mac writes points to a different stage than a callback followed by a failed read; it alone does not prove which iOS policy delayed delivery.

These tests establish recovery behavior at the SDK boundary and simulator lifecycle behavior. They do not simulate APNs scheduling or prove real-device background delivery latency.

## Further options and the evidence required

### Separate known-Mac updates from discovery

This is the next small candidate if logs show query latency consuming a material part of the phone's 20-second read budget. Current `fetch` still awaits discovery before its direct batch. Reading known Macs independently could keep their readings current while new-Mac discovery is delayed.

It needs an explicit distinction between a partial update and an authoritative account snapshot. Otherwise, a partial response could incorrectly remove other Macs or leave an erased Mac indefinitely. Before implementation, require a regression where discovery stalls but a known-record read succeeds, plus tests for deletion, late command answers, account changes, cancellation and new-Mac discovery. There is currently no measurement showing this stage caused the reported incident, so this assessment does not add that more complex path.

### Reduce irrelevant change hints

The current zone subscription includes `MacStatus`, `Command` and `Event`, including event cleanup. Record-type scoping is supported by the record-zone subscription API. Separate status and command subscriptions could reduce irrelevant callbacks, but every current client shares the broad `remote-zone` identifier. Changing its scope unilaterally would break the other reader's expectations, and older clients could restore it. Measure callback types first; any migration needs compatibility tests across Mac and phone versions. This is a potential efficiency improvement, not a demonstrated way to raise iOS's delivery budget.

### CKSyncEngine and incremental zone changes

[CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5) is a credible way to delegate subscription, account, retry and change-token management as the data model grows. It still uses silent notifications and an indeterminate system scheduler. Migration would require durable engine state, account-scoped cache handling, deletion reconciliation and a measured first-sync/recovery path; keep command acknowledgement reads direct.

Incremental [record-zone changes](https://developer.apple.com/documentation/cloudkit/ckfetchrecordzonechangesoperation) can reduce repeated reads when there are many Macs or records. Apple documents token persistence, pagination and initial fetch behavior. Do not assume every historical heartbeat is necessarily returned as a separate payload, or claim a speed-up without measurement. Benchmark first contact, long gaps and token expiration against the current bounded query/direct-read path before replacing it. Neither option is an established fix for suspended-phone freshness.

### Direct nearby communication

Apple recommends [Network framework for new peer-to-peer work](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api). A local connection could improve foreground responsiveness or work without internet when devices are nearby. It adds discovery, permissions, peer authentication and network-transition handling. Multipeer Connectivity's [sessions disconnect when the app backgrounds](https://developer.apple.com/documentation/multipeerconnectivity), so it is not a replacement for locked-phone updates.

[Core Bluetooth on iOS 26](https://developer.apple.com/documentation/corebluetooth) offers additional foreground-like privileges while an app has a Live Activity. However, an [Apple engineer's clarification](https://developer.apple.com/forums/thread/815189) says an inactive, fully locked display restores scan restrictions. Connected characteristic notifications and service-filtered reconnection are possible subjects for a nearby-only prototype; they have not been validated here. No physical iPhone was available in this session. Require locked-screen notification delivery, range loss/recovery, battery measurements and authenticated peers before proposing it for production. Preserve CloudKit for remote access and older supported iOS versions.

Wi-Fi Aware availability annotations are insufficient evidence of Mac support: an [Apple DTS explanation](https://developer.apple.com/forums/thread/827887) distinguishes framework presence from runtime hardware capability. It is not a validated Mac-to-iPhone replacement in this assessment.

### ActivityKit push provider

If frequent remote lock-screen updates become a product requirement, [ActivityKit-specific APNs pushes](https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications) are the supported mechanism for updating an activity without first waking the app to fetch CloudKit. Delivery still has system/network limits and the activity's duration limit remains.

Sending directly from every distributed Mac would require provider credentials. Apple requires the [APNs signing key to remain private](https://developer.apple.com/documentation/usernotifications/establishing-a-token-based-connection-to-apns); embedding the developer's key in the client is unsuitable. A credential-holding provider is therefore a separate architecture choice, with operating and privacy responsibilities, rather than a free configuration change to the CloudKit subscription. It is not introduced here.

## What to measure next

Use a physical iPhone and the local logs before setting a freshness promise. Follow one Mac sample through successful CloudKit write, phone callback arrival, direct read and activity submission. Exercise screen off, Low Power Mode, disabled background refresh, network changes, long sessions and relaunch. Record each stage independently: read latency after a wake must not be confused with the time spent waiting for a wake.

Adopt another transport only if it improves the measured failing stage and passes the relevant recovery/security tests. The immediate implementation strengthens the existing serverless design; it does not promise a continuously executing phone app.
