# Nearby communication and automatic handoff

Implemented on `feat/nearby-remote-handoff`, based on the CloudKit recovery work in PR #57. This adds transports without an additional service. It does not establish the cause of the earlier daytime incident.

## Which path is used

| Situation | Status | Commands |
| --- | --- | --- |
| Reachable local network, phone app open | LAN and CloudKit continue independently; BLE can also remain connected | Healthy authenticated LAN, then BLE, then CloudKit |
| Phone on cellular, Mac on office Wi-Fi, within Bluetooth range | BLE and CloudKit | BLE, then CloudKit |
| Different networks and outside Bluetooth range | CloudKit | CloudKit |
| Local permission denied, radio off or network isolation | Remaining available transports | Skip unavailable paths and continue |
| Internet unavailable after trust was cached | An established/discoverable nearby path | Nearby; no CloudKit fallback without internet |

LAN includes Wi-Fi and Ethernet, including a Mac connected by Ethernet and a phone on the same reachable Wi-Fi network. Guest isolation, a firewall or multicast filtering can prevent Bonjour discovery even on the same named network. Network framework enables peer-to-peer interfaces as well, but that capability is not a tested promise of internet-free discovery between arbitrary hardware.

`NearbyClient` keeps independently authenticated LAN and BLE connections. It selects only connections with authenticated traffic within 90 seconds. The Mac sends a fresh status to connected peers every 30 seconds, independently of CloudKit publication throttling; the phone acknowledges these samples. No status sampling is performed by this ticker when nobody is connected. Foreground discovery/reconnect and Mac listener/advertising recovery retry at 30-second intervals. Native Core Bluetooth maintains a pending reconnect after an established connection drops. Returning connectivity therefore makes a route eligible again without a manual transport switch.

Commands have one 36-second deadline. A LAN/BLE attempt gets up to three seconds, or eight seconds for Inspect, then the next route receives the same immutable request. CloudKit gets the remaining time. Cancellation stops handoff; an explicit Mac failure is returned rather than retried through a different path. Neither transport owns a Keep Awake lease: a radio or socket disconnect does not end work on the Mac.

## Trust and data handling

The Mac creates a random 256-bit credential when iPhone sharing is enabled. Its own Keychain stores the credential with `AfterFirstUnlockThisDeviceOnly`, bound to the verified CloudKit account ID. The phone obtains it from that Apple Account's private CloudKit database and saves the same account binding in its own Keychain. First trust setup needs working iCloud and matching CloudKit environments. Both apps verify the account identity once per process and after an account-change notification before reusing cached credentials; a change while an app was closed cannot silently inherit the previous account's key. A failed identity check leaves nearby access unavailable and is retried. Cached trust supports internet loss after verification; a cold launch without a successful account check does not enable nearby access.

Credential records reuse the deployed `Command` type and its existing `encryptedValues["payload"]`, at `nearby.<macID>.<key fingerprint>`. They are outside the command mailbox. Immutable names keep a late publication of an earlier key from overwriting its replacement. Public status carries only the supported nearby protocol version and an opaque key fingerprint. Secrets are not stored in status, widgets, defaults, Bonjour names or logs. Service identifiers are stable pseudonyms for the lifetime of a credential and can be observed by nearby scanners.

LAN uses Network framework TLS with a pre-shared key; certificate checking is not bypassed. Both LAN and BLE also use a fresh, mutually authenticated challenge/response session. HMAC-SHA256 authenticates the challenge, HKDF derives separate directional keys, and ChaChaPoly protects payloads with monotonic sequence numbers. Replayed proofs, reflected packets, out-of-order packets and tampering close the connection before application dispatch. Frames, queued bytes, pending requests, handshake time, connections and outstanding delivery acknowledgements are bounded.

Turning sharing off closes the listeners and connections, deletes the Mac's Keychain credential and retries withdrawal of its CloudKit records. Turning it on creates a new credential. An Apple Account change invalidates local trust and account caches; phone readings and activities are cleared. Removing a Mac on the phone removes its cached credential and connections. An active sharing Mac can reappear, as it already did through CloudKit; Remove Mac is not permanent revocation. To revoke nearby access, turn off sharing on that Mac.

The credential authorizes the account's trusted phones, rather than an individual phone ACL. Removing a device from an Apple Account is not an immediate cryptographic revocation of a cached nearby key. Turn sharing off/on on the Mac to rotate that capability. The session protocol does not provide forward secrecy if the long-lived credential is later extracted; Keychain protection and explicit rotation remain relevant controls.

## One command admission path

CloudKit, LAN and BLE all call `RemoteAccessModel.executeCommand`. A durable, atomic journal claims an ID and its arguments before performing any effect. Results are scoped by verified account identity while sample revisions continue across accounts. An overlapping duplicate waits for the existing operation; a later duplicate receives its cached result with a fresh status. Reusing an ID with different arguments is rejected. A different simultaneous command is refused as busy. Request size, age and journal capacity are bounded.

If the Mac crashes after admission but before saving its result, the next attempt reports that the outcome is uncertain and does not repeat the change. This avoids adding 30 minutes twice, but can also mean an admitted command was never applied. It is at-most-once admission within the accepted request lifetime, not a promise that every requested effect completes. Losing or manually deleting the local journal is outside that guarantee.

Every outgoing sample receives a durable revision before asynchronous history/settings enrichment. The phone rejects older revisions across all transports; older Mac versions fall back to timestamps. A nearby update is explicitly partial, so it cannot erase another Mac. Updates enter the same serialized reconciliation path used by widgets, alerts and Live Activities. CloudKit publishing and subscriptions continue while nearby paths work, preserving access when the devices separate.

CloudKit timeout cleanup matches the command ID and conditionally clears the fetched record. A newer command from another phone is preserved. A sleep command waits for a successful CloudKit publication or its nearby reply acknowledgement before asking macOS to sleep.

## Phone lifecycle and permissions

Both apps declare Local Network and Bluetooth usage descriptions; Bonjour is limited to `_battistics._tcp`. The Mac retains its existing accessory-battery Bluetooth use. Permission is requested by native APIs when the relevant feature starts; denying it leaves CloudKit available.

The phone stops LAN discovery and connections when backgrounded. BLE uses `bluetooth-central`, filtered service discovery, characteristic notifications and a restoration identifier. Restored connections are re-established to negotiate fresh process-local session keys after the central manager is powered on. No audio loop, artificial location activity or permanent phone timer keeps the app alive. Apple documents [central-role background processing and state restoration](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html); these permit event handling rather than continuous app execution.

Bluetooth discovery retains at most eight candidates and at most two untrusted candidates per Mac. Discovery/setup has a deadline; failed authentication frees its slot. Transient setup has a bounded retry, and authenticated connection loss uses a native pending reconnect. Rejected restored connections are canceled once the manager is powered on. On the Mac, pending TLS handshakes have a separate eight-connection budget and only completed TLS-PSK handshakes reach application admission. New candidates may replace unauthenticated pending peers, but cannot evict authenticated peers. These bounds address application cache/slot exhaustion; they do not claim resistance to sustained radio interference or denial of service on a shared network.

iOS can delay discovery and background delivery or terminate the app. Force-quitting, disabled Bluetooth/background access, range loss, or radio contention can interrupt the nearby path. CloudKit silent delivery retains its own scheduling limits. The new transports do not bypass ActivityKit's active duration or guarantee uninterrupted Lock Screen freshness. There is no APNs provider credential embedded in either app.

## Validation

Automated checks cover:

- Mutual authentication, wrong keys/Mac IDs, replay/reflection/reordering, tampering, fragmentation and frame limits.
- A real Network framework TLS connection on loopback, encrypted command/response and rejection of an incorrect TLS key before command dispatch.
- Lost LAN reply followed by BLE with the same request: an extension has exactly one effect. Stalled local work falls through within its budget; cancellation and explicit refusal do not resend.
- Heartbeat and command acknowledgements over a fragmented stream, recovery after a delayed phone wake, pending-command release on disconnect and session closure at the reply deadline. The Mac keeps sending to authenticated connections after the health window expires so a delayed BLE wake is not stranded.
- Durable replay protection and revisions across relaunch, interrupted admission, argument collisions, expired/future requests and failed persistence.
- CloudKit credential round-trip using the existing encrypted schema and conditional cleanup that preserves another phone's command.
- Account identity caching/invalidation, failed verification and rejection of a late response belonging to the previous account.
- iOS partial-snapshot reconciliation, rejecting an older CloudKit revision, plus the existing Live Activity and notification lifecycle tests.
- The real Mac controller in an isolated app: repeated start/extend requests preserve one session and one extension, and revisions advance. Production Battistics is left running; the harness uses no iCloud or nearby radios and does not install the helper.

Follow-up review on 2026-11-15 added regression coverage and fixed queued revoked-peer dispatch, authorization after suspended startup/helper preflight, cross-account command/result/outbox state, phone fallback/cleanup after an account change, and withdrawal intent persistence. Account/zone epochs prevent late completions from preparing or updating replacement-account caches. A deliberately altered disposable fixture with the host's dispatch guard removed fails the revoked/disconnected-peer regressions; the guarded implementation passes. An initially suspected CloudKit re-ack suppression was rejected: `lastCommand` participates in `differsNoticeably`, and the comparison baseline changes only after successful publication.

Re-enabling sharing also waits for an earlier withdrawal attempt before new status, command polling or nearby credential publication begins. Account/session invalidation drops the Mac model's stale retry deadline and errors; CloudKit retains its own server backoff for an unchanged account. BLE discovery keeps its canonical peripheral object so a repeated advertisement cannot replace a live session's delegate/characteristics.

Withdrawal first joins SDK writes already in flight for status, nearby credentials and alerts, including writes whose callers have been canceled. It tracks only the SDK operations, so a queued publisher waiting for withdrawal cannot deadlock the barrier. The controller harness covers successful and failed writes finishing before deletion, followed by replacement publication. After those bounded writes and account verification, deletion has a five-second SDK budget. Command cleanup conditionally clears the observed request instead of blindly deleting the shared mailbox; a newer phone command is preserved. A failed withdrawal remains pending for retry. Native Core Bluetooth cancellation/deallocation during an unfinished restoration remains a hardware-validation case; source review alone does not establish every native-handle cleanup ordering.

The final local run passes 319 Swift tests in 39 suites and all seven iOS simulator tests; macOS/iOS app builds and the isolated English/Turkish Mac-controller harness pass. Sixty-four focused protocol/admission/account tests also pass in an OS sandbox with external and loopback networking denied, an empty allowlisted environment, scratch-only writes, a fixed 768 MiB scratch volume, and CPU/address-space/process/file/wall-time bounds. This is focused review of this PR, rather than complete coverage of the whole product or a formal cryptographic proof.

An owner-authorized, separately signed diagnostic app on a physical iPhone 17 running iOS 27.2 exercised the production nearby transport code with ephemeral fixture credentials and synthetic Mac status. Real LAN and BLE authenticated; the same extension request sent through both had one effect and one cached response. A BLE command succeeded with LAN disabled in the client. XCUITest switched the phone from its existing Hotspot to the known Wi-Fi and back, observed advancing samples and a successful BLE command, and restored the original network. Mac network settings and the installed production apps were left untouched. This diagnostic bypasses CloudKit account bootstrap and does not exercise actual power/helper changes.

The owner then locked the phone. During a 150-second observation window (15:17:56–15:20:26 UTC), six new callbacks were persisted with `UIApplication.State.background`; three arrived while BLE was the client's only healthy route. Those samples' Mac collection and phone processing times differed by 0–1 seconds at the fixture's timestamp resolution. The phone app was not foregrounded to collect the file. This establishes short-run background transport delivery on that device, not a latency promise or the complete Production CloudKit → Live Activity path. The temporary UI fixture's first BLE-mode preparation failed; the control was corrected and its repeated preparation passed before the locked-window measurement.

Before release, still verify Production iCloud credential provisioning and the full background Live Activity update, permission-denial recovery, range loss/return, OS termination/restoration, sharing revocation and account changes on hardware, energy impact and long sessions. The short device runs do not establish a delivery latency bound, an eight-hour freshness promise or a battery-use result. Thirty seconds is the Mac's send interval, not a background delivery guarantee.

The broader [serverless reliability assessment](remote-reliability.md) retains the evidence for CKSyncEngine, subscription changes and a possible ActivityKit provider. Those alternatives remain unimplemented and require evidence before a migration.
