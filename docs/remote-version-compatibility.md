# Companion app version compatibility

The iPhone's Nearby Connections screen shows this iPhone's app version/build and each Mac's last reported app version/build. The Mac's iPhone settings pane shows its own version/build and the last app-version report from each reporting iPhone. Update guidance names the device, app and minimum compatible version. These checks concern connection compatibility, rather than a live catalogue of every newer App Store or GitHub release.

Battistics includes optional `appInfo` in its normal status payload, so it travels through private iCloud and authenticated nearby connections. Older readers ignore the extra field. Remote also reports its app version, minimum required Mac version, supported nearby protocol and app-generated installation ID after a successful foreground iCloud read. It uses the existing encrypted `Command.payload` schema at `phones.<macID>`, outside the command mailbox; no new CloudKit fields or production schema migration are required.

Each Mac reads the roster with its status and command in one named-record fetch. Phones merge reports using conditional saves and up to three conflict attempts, preserving other phones. The roster contains at most eight reports. Entries older than 30 days are hidden on read and pruned on a later report; age alone does not delete the encrypted CloudKit record. Foreground reports are limited to eight Macs per pass and once per Mac per five minutes per process. Backgrounding cancels pending reporting work while preserving the cadence, and silent-push reads never generate a version report. The app-generated ID is not a hardware identifier or credential. Version metadata stays in the user's private iCloud and does not authorize a connection or command.

Sharing withdrawal and removing a Mac delete its roster. An in-flight report can race another device's deletion; a report checks that the Mac status still exists before writing, and any remaining metadata is bounded and expires. Account changes cancel phone reporting, invalidate its epoch, and clear the Mac's displayed roster. Late previous-account results cannot trigger a replacement-account write. Sample mode cancels reporting and never publishes sample devices.

The nearby minimums remain Battistics **1.6.0** and Remote **1.1.0**. A peer may advertise a higher minimum in a future build, which produces a local-app update notice. Unknown or malformed versions are not labelled outdated. Previously released apps that did not send version information cannot retroactively supply their exact installed version; they appear as **Version not shared** until updated to a reporting build. Reports are labelled with their observation time and do not mean a phone is currently online. Permission denial, not-yet-requested permissions and incomplete nearby setup are separate from version compatibility.

Source/SDK-boundary tests cover numeric SemVer comparison, legacy status decoding, roster bounds/expiry, concurrent-phone merge conflicts and account changes before and during a report. The existing physical delivery/energy follow-up remains [issue #60](https://github.com/doguyilmaz/battistics/issues/60); version reporting does not establish natural background delivery or energy performance.

## Validation on 2026-11-16

- 129 focused remote/CloudKit tests passed, including an unreadable optional roster leaving the command slot usable.
- All seven iOS tests passed in Xcode's `.xcresult` with zero failures. The scheduling test initially waited for the fresh simulator's notification authorization; granting it through the device session allowed the test to complete successfully.
- macOS and iOS Simulator Debug builds passed. The isolated Mac controller harness passed in English and Turkish, with its app-version metadata read from the project configuration.
- Native EN/TR screens were inspected on both platforms. iPhone fixtures exercise a Mac requiring a newer phone app, a compatible Mac, and an older Mac requiring an update. Mac fixtures exercise compatible and older phone versions. These are synthetic version fixtures, not a live paired-device Production iCloud run.
- Both localization catalogs compiled, the privacy documentation site built, and `git diff --check` passed. Local receipts and screenshots are in ignored `.build/` paths.

This is unreleased source. The existing iOS 1.1.0 (18) review submission and public Mac release are not replaced by this change. Reporting becomes available after the corresponding app builds are distributed; legacy apps do not gain version-reporting capability remotely.
