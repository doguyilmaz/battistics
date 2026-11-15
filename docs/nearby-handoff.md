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

## One command admission path

CloudKit, LAN and BLE all call `RemoteAccessModel.executeCommand`. A durable, atomic journal claims an ID and its arguments before performing any effect. An overlapping duplicate waits for the existing operation; a later duplicate receives its cached result with a fresh status. Reusing an ID with different arguments is rejected. A different simultaneous command is refused as busy. Request size, age and journal capacity are bounded.

If the Mac crashes after admission but before saving its result, the next attempt reports that the outcome is uncertain and does not repeat the change. This avoids adding 30 minutes twice, but can also mean an admitted command was never applied. It is at-most-once admission within the accepted request lifetime, not a promise that every requested effect completes. Losing or manually deleting the local journal is outside that guarantee.

Every outgoing sample receives a durable revision before asynchronous history/settings enrichment. The phone rejects older revisions across all transports; older Mac versions fall back to timestamps. A nearby update is explicitly partial, so it cannot erase another Mac. Updates enter the same serialized reconciliation path used by widgets, alerts and Live Activities. CloudKit publishing and subscriptions continue while nearby paths work, preserving access when the devices separate.

CloudKit timeout cleanup matches the command ID and conditionally clears the fetched record. A newer command from another phone is preserved. A sleep command waits for a successful CloudKit publication or its nearby reply acknowledgement before asking macOS to sleep.

## Phone lifecycle and permissions

Both apps declare Local Network and Bluetooth usage descriptions; Bonjour is limited to `_battistics._tcp`. The Mac retains its existing accessory-battery Bluetooth use. Permission is requested by native APIs when the relevant feature starts; denying it leaves CloudKit available.

The phone stops LAN discovery and connections when backgrounded. BLE uses `bluetooth-central`, filtered service discovery, characteristic notifications and a restoration identifier. Restored connections are re-established to negotiate fresh process-local session keys after the central manager is powered on. No audio loop, artificial location activity or permanent phone timer keeps the app alive. Apple documents [central-role background processing and state restoration](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html); these permit event handling rather than continuous app execution.

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

These are protocol, controller, simulator and loopback checks. They do not validate physical BLE radio behavior, Bonjour across real routers, iCloud credential provisioning in Production, energy use or locked-screen delivery latency. No physical iPhone was available. Before release, verify a signed Mac/iPhone pair through permission grant/denial, Wi-Fi-to-cellular transitions, range loss/return, screen lock, OS termination/restoration, sharing revocation, account changes and long sessions. Measure energy impact and actual callback-to-activity timing; 30 seconds is the Mac's send interval, not a background delivery guarantee.

The broader [serverless reliability assessment](remote-reliability.md) retains the evidence for CKSyncEngine, subscription changes and a possible ActivityKit provider. Those alternatives remain unimplemented and require evidence before a migration.
