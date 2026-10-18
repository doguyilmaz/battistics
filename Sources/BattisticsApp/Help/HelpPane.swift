import SwiftUI

struct HelpPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @State private var assistant = HelpAssistantModel()

    private var articles: [HelpArticle] { HelpArticle.matching(query) }

    var body: some View {
        Form {
            Section {
                HStack {
                    Label("Make yourself at home", systemImage: "sparkle.magnifyingglass")
                    Spacer()
                    Button("Take a Tour…") { model.tourRequested = true }
                }
                Text("Learn the controls in a short guided tour, or find an answer below.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Ask Battistics") {
                TextField("Search help or ask a question", text: $query, axis: .vertical)
                    .lineLimit(1...3)
                    .onSubmit { assistant.ask(query) }
                Text(assistant.availabilityMessage).font(.caption).foregroundStyle(.secondary)
                HStack {
                    if assistant.isResponding {
                        ProgressView().controlSize(.small)
                        Text("Thinking on this Mac…").font(.caption)
                        Spacer()
                        Button("Cancel") { assistant.cancel() }
                    } else {
                        Button("Ask On-Device AI") { assistant.ask(query) }
                            .disabled(!assistant.available || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || query.count > 600)
                        Spacer()
                        if !assistant.available {
                            Button("Check Availability") { assistant.refreshAvailability() }
                        }
                    }
                }
                if query.count > 600 {
                    Text("Keep your question under 600 characters.").font(.caption).foregroundStyle(.secondary)
                }
                if let answer = assistant.answer {
                    Text(answer).textSelection(.enabled)
                    Text("AI selected this answer from the built-in guide on this Mac. Check the source if it does not answer your question.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = assistant.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
            if !assistant.sources.isEmpty {
                Section("Source Articles") {
                    ForEach(assistant.sources) { article in articleRow(article) }
                }
            }
            Section("Built-in Answers") {
                if articles.isEmpty {
                    Text("No matching articles. Try battery, sleep, heat, history, or assistant.")
                        .foregroundStyle(.secondary)
                    Button("Show All Answers") { query = "" }
                } else {
                    ForEach(articles) { article in articleRow(article) }
                }
            }
        }
        .formStyle(.grouped)
        .task { assistant.refreshAvailability() }
        .onChange(of: scenePhase) { if scenePhase == .active { assistant.refreshAvailability() } }
        .onDisappear { assistant.cancel() }
    }

    private func articleRow(_ article: HelpArticle) -> some View {
        DisclosureGroup(article.title) {
            VStack(alignment: .leading, spacing: 10) {
                Text(article.answer).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Open \(article.pane.title)") { model.dashboardPane = article.pane }
            }
            .padding(.vertical, 6)
        }
    }
}
