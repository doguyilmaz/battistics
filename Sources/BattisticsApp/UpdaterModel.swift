import Combine
import Sparkle
import SwiftUI

/// Sparkle 2 wrapper. The updater starts with the app and honors the
/// auto-check / auto-download preferences, which Sparkle persists itself.
@MainActor
@Observable
final class UpdaterModel {
    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()

    private(set) var canCheckForUpdates = false
    /// Sparkle's own record. It checks on a 24 hour schedule measured from
    /// this date rather than at launch, so without showing it there is no way
    /// to tell a working updater from a broken one.
    private(set) var lastCheckDate: Date?

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &cancellables)
        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .sink { [weak self] value in
                self?.lastCheckDate = value
            }
            .store(in: &cancellables)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesButton: View {
    var updater: UpdaterModel

    var body: some View {
        Button("Check for Updates…") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}
