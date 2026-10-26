import AppIntents
import WidgetKit

/// The Mac a widget shows, chosen while editing the widget.
struct WidgetMac: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Mac"
    static let defaultQuery = WidgetMacQuery()
    static let selected = WidgetMac(id: "selected", name: String(localized: "Chosen in App"))

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct WidgetMacQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetMac] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [WidgetMac] {
        [.selected] + SharedSnapshot.loadAll().compactMap { snapshot in
            snapshot.macID.map { WidgetMac(id: $0, name: snapshot.macName) }
        }
    }

    func defaultResult() async -> WidgetMac? { .selected }
}

struct MacWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Mac"
    static let description = IntentDescription("Choose which Mac the widget shows.")

    @Parameter(title: "Mac") var mac: WidgetMac?

    /// The chosen Mac's latest reading; the one chosen in the app when that
    /// is the choice or the Mac was removed.
    var snapshot: SharedSnapshot? {
        let chosen = mac.flatMap { mac in SharedSnapshot.loadAll().first { $0.macID == mac.id } }
        return chosen ?? SharedSnapshot.load()
    }
}
