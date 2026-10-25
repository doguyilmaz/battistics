import BattisticsRemote
import SwiftUI

/// Presented when no Macs have reported to iCloud yet.
/// Provides instant access to This iPhone telemetry, Mac download links,
/// pairing instructions, and interactive connection diagnostics.
struct SetupIntro: View {
    @Environment(MacStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var phone = LocalPhoneMonitor.shared
    @State private var showingTroubleshooting = false

    private let macDownloadURL = URL(string: "https://github.com/doguyilmaz/battistics/releases/latest")!
    private let projectURL = URL(string: "https://github.com/doguyilmaz/battistics")!

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroHeader

                thisPhoneCard

                macSetupCard

                diagnosticsCard

                troubleshootingSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(String(localized: "Setup & Devices"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.refreshAll()
        }
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 76, height: 76)
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.top, 4)

            Text("Your Mac on your iPhone")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("See your Mac’s battery and control Keep Awake through your own iCloud.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    // MARK: - This iPhone Shortcut Card

    private var thisPhoneCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.green.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Image(systemName: "iphone.gen3")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(phone.pickerDisplayName)
                        .font(.headline)
                    Text("Battery health, cycles, voltages & specs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(phone.percent)%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.green)
            }

            Text("Don’t have a Mac nearby? You can explore this iPhone’s battery health, thermal level, cycles, memory and storage right away.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button {
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    phone.refresh()
                    store.selectedID = MacStore.localPhoneID
                }
            } label: {
                HStack {
                    Image(systemName: "gauge.with.needle.fill")
                    Text("Open This iPhone Dashboard")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.green.opacity(0.20), lineWidth: 1)
        )
    }

    // MARK: - Mac Setup Card

    private var macSetupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Setup Battistics on Mac", systemImage: "macbook")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                stepRow(number: 1, title: String(localized: "Install Battistics on your Mac"), detail: String(localized: "Download and launch Battistics on macOS 14 Sonoma, macOS 15 Sequoia or later."))

                stepRow(number: 2, title: String(localized: "Enable Remote Companion"), detail: String(localized: "In Battistics on Mac › Settings › iPhone, toggle on 'Show this Mac in Battistics Remote'."))

                stepRow(number: 3, title: String(localized: "Same Apple Account"), detail: String(localized: "Ensure this iPhone and your Mac are signed in to iCloud with the same Apple ID."))
            }

            Divider()

            HStack(spacing: 10) {
                Link(destination: macDownloadURL) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Get for Mac")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)

                ShareLink(
                    item: macDownloadURL,
                    subject: Text("Battistics for Mac"),
                    message: Text("Download Battistics for Mac to monitor your battery and control Keep Awake from your iPhone: \(macDownloadURL.absoluteString)")
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Link")
                            .font(.subheadline.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 34)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Diagnostics Card

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Connection & iCloud", systemImage: "network")
                    .font(.headline)
                Spacer()
                if store.refreshing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            VStack(spacing: 8) {
                diagnosticRow(
                    label: String(localized: "iCloud Sync"),
                    status: store.problem == nil ? String(localized: "Working") : String(localized: "Not syncing"),
                    isOk: store.problem == nil
                )

                diagnosticRow(
                    label: String(localized: "Mac Records"),
                    status: store.macs.isEmpty ? String(localized: "None yet") : String(localized: "\(store.macs.count) found"),
                    isOk: !store.macs.isEmpty
                )
            }

            if let problem = store.problem {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                Task { await store.refreshAll() }
            } label: {
                HStack {
                    if store.refreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(store.refreshing ? String(localized: "Looking for your Mac…") : String(localized: "Check Again"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 34)
            }
            .buttonStyle(.bordered)
            .disabled(store.refreshing)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Troubleshooting Section

    private var troubleshootingSection: some View {
        DisclosureGroup(isExpanded: $showingTroubleshooting) {
            VStack(alignment: .leading, spacing: 10) {
                troubleTip(
                    title: String(localized: "Is your Mac sleeping or lid closed?"),
                    desc: String(localized: "A Mac must be awake with Battistics open at least once to broadcast its initial state to iCloud. Once connected, Keep Awake works even with the lid closed.")
                )

                troubleTip(
                    title: String(localized: "Using different Apple Accounts?"),
                    desc: String(localized: "Battistics Remote communicates privately via your personal CloudKit database. Both devices must be logged into the same Apple ID.")
                )

                troubleTip(
                    title: String(localized: "Is iCloud Drive enabled?"),
                    desc: String(localized: "Check System Settings › Apple Account › iCloud on both your Mac and iPhone to ensure iCloud Drive and Sync are turned on.")
                )
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
                Text("Troubleshooting Guide")
                    .font(.subheadline.weight(.medium))
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Helper Views

    private func stepRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: Circle())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func diagnosticRow(label: String, status: String, isOk: Bool) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
            Spacer()
            HStack(spacing: 4) {
                Circle()
                    .fill(isOk ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func troubleTip(title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(desc)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
