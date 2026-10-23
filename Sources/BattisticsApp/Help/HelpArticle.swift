import Foundation

enum HelpArticle: String, CaseIterable, Identifiable {
    case keepAwake, lowBattery, warnings, heat, helper, health, history, privacy, automation
    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepAwake: String(localized: "Which Keep Awake mode should I choose?")
        case .lowBattery: String(localized: "Can Keep Awake stop at a battery percentage?")
        case .warnings: String(localized: "Why did my Mac sleep when I turned Keep Awake off?")
        case .heat: String(localized: "Can Battistics cool my Mac or control its fans?")
        case .helper: String(localized: "Why does closed-lid mode need permission?")
        case .health: String(localized: "Why do battery health readings differ?")
        case .history: String(localized: "Where is my history and how can I export it?")
        case .privacy: String(localized: "Does the assistant send my data anywhere?")
        case .automation: String(localized: "Can I keep a development task awake until it finishes?")
        }
    }

    var answer: String {
        switch self {
        case .keepAwake:
            String(localized: "In Power, choose Keep the display on for presentations, Let the display sleep for downloads, or Stay awake with the lid closed for closed-lid work. Pick a duration, then enable Keep Awake. Changing the duration during a session applies it from that moment. Closed-lid mode needs the power helper and works on battery or adapter. An empty battery can still interrupt any mode.")
        case .lowBattery:
            String(localized: "Yes. In Power → Session Protection, enable Stop Keep Awake on low battery and choose 5–50%. It is off by default, with 10% preselected. At or below the level, on battery power, Battistics ends the session and allows normal sleep. It never shuts down the Mac or closes apps. The rule needs Battistics running and a valid battery reading; it cannot guarantee protection against sudden power loss.")
        case .warnings:
            String(localized: "Ending Keep Awake restores normal sleep behavior. With the lid closed, the Mac may sleep immediately. That alone does not prove a shutdown or battery fault. At very low charge, connect power before ending the session and save your work. Session Protection can warn at a chosen percentage, at least 5 points above an enabled stop level. A sudden drop may skip the warning. Notifications need macOS permission; an in-app notice is also shown.")
        case .heat:
            String(localized: "Battistics does not change fan speeds. Battistics warns during a Keep Awake session when macOS reports serious or critical thermal pressure. In Power → Thermal Care you can optionally end Keep Awake at that point, on battery or adapter. This uses system thermal pressure, not the battery temperature reading. Keep vents clear, use a hard surface, open the lid, and reduce heavy work. Never keep a running closed Mac inside a bag. Thermal Care is not a hardware diagnosis or a guarantee against overheating.")
        case .helper:
            String(localized: "Closed-lid Keep Awake temporarily changes a privileged system sleep setting. Approve the power helper in System Settings → General → Login Items & Extensions when prompted. The helper restores the setting after the session; if Battistics quits or crashes, its lease expires within about 45 seconds. An external change is left alone. If the helper is unavailable, use Repair in Power. Developer builds without a signing team cannot register the helper.")
        case .health:
            String(localized: "Battery capacity is an estimate that shifts with temperature, charge, and controller calibration. Battistics shows controller-based health alongside Apple's separately modeled verdict. Small daily changes do not necessarily mean wear. History helps reveal longer trends; battery temperature is not CPU or enclosure temperature. Battistics does not diagnose hardware faults.")
        case .history:
            String(localized: "History shows charge, power, temperature, and health trends recorded locally. New installations need time to collect samples. In Data you can export or import CSV, delete history, and control optional power recording. Turning off power recording does not turn off Keep Awake protection. Energy shows busy apps only while its view is open.")
        case .privacy:
            String(localized: "Built-in help works offline on macOS 14 and later. The optional assistant uses Apple's on-device Foundation Models on macOS 26 or later when Apple Intelligence, its model, and the language are available. AI selects a relevant guide article; the answer is the reviewed guide text, not generated instructions. It cannot change settings and has no cloud fallback. Questions and answers are not saved by Battistics. If the selection does not answer your question, browse the source articles. Optional update checks are separate.")
        case .automation:
            String(localized: "Yes. Enable Local automation in Power. Copy Terminal setup to use battistics run for a build or script; its exit ends Keep Awake, with a maximum of 12 hours. For an interactive AI terminal, copy the MCP configuration into a trusted client and ask it to start a task before work and stop it afterward. An open process alone cannot detect task completion. Manual stops, time limits, disconnection and battery or thermal protection can end Keep Awake sooner without killing your command. Closed-lid tasks require separate permission and an installed helper. Keep Battistics open.")
        }
    }

    var pane: DashboardPane {
        switch self {
        case .keepAwake, .lowBattery, .warnings, .heat, .helper, .automation: .system
        case .health: .overview
        case .history: .data
        case .privacy: .about
        }
    }

    private var keywords: String {
        switch self {
        case .keepAwake: "awake sleep lid display mode duration uyku uyanık kapak ekran süre mod"
        case .lowBattery: "battery percent shutdown stop charge pil batarya yüzde kapat durdur şarj"
        case .warnings: "warning notification sudden off sleep shut uyarı bildirim aniden kapandı uyudu"
        case .heat: "fan hot heat temperature thermal cool sıcak ısın ısı soğut termal"
        case .helper: "helper permission admin repair power yardımcı izin yönetici onar yetki"
        case .health: "health capacity cycle wear calibration sağlık kapasite döngü aşınma kalibrasyon"
        case .history: "history csv export import data energy geçmiş veri dışa içe aktar enerji"
        case .privacy: "assistant intelligence ai privacy offline local asistan zeka gizlilik çevrimdışı yerel"
        case .automation: "mcp agent task project code build terminal automation görev proje otomasyon iş"
        }
    }

    static func matching(_ query: String) -> [HelpArticle] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allCases }
        let stopWords: Set<String> = ["the", "can", "how", "why", "does", "this", "that", "with", "from", "for", "and", "what", "you", "your", "bir", "nasıl", "neden", "için", "ile", "miyim", "misin"]
        let words: [String] = query.prefix(600).split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init).filter { $0.count >= 3 || ["ai", "iş"].contains($0.lowercased()) }
            .filter { !stopWords.contains($0.lowercased()) }
        var ranked: [(article: HelpArticle, score: Int)] = []
        for article in allCases {
            let primary = "\(article.title) \(article.keywords)"
            var score = 0
            for word in words {
                if primary.localizedCaseInsensitiveContains(word) { score += 3 }
                if article.answer.localizedCaseInsensitiveContains(word) { score += 1 }
            }
            if score > 0 { ranked.append((article, score)) }
        }
        ranked.sort { lhs, rhs in
            lhs.score == rhs.score ? lhs.article.rawValue < rhs.article.rawValue : lhs.score > rhs.score
        }
        return ranked.map(\.article)
    }
}
