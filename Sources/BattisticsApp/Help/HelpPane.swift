import SwiftUI

struct HelpPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var query = ""
    @State private var assistant = HelpAssistantModel()
    @State private var askedEmpty = false
    @FocusState private var fieldFocused: Bool

    private var articles: [HelpArticle] { HelpArticle.matching(query) }
    private var question: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Form {
            Section {
                HStack {
                    Button("Take a Tour…") { model.tourRequested = true }
                    if let url = URL(string: "https://battistics.apps.doguyilmaz.com/docs/") {
                        Link(destination: url) {
                            Label("Read the Documentation Online", systemImage: "book")
                        }
                    }
                    Spacer()
                }
            }
            Section {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search help or ask a question", text: $query, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...3)
                        .focused($fieldFocused)
                        .onSubmit(ask)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(.background, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(fieldFocused ? Color.accentColor : .secondary.opacity(0.4)))
                .tourTarget(.help)
                .onChange(of: query) { if !question.isEmpty { askedEmpty = false } }
                HStack {
                    if assistant.isResponding {
                        ProgressView().controlSize(.small)
                        Text("Thinking on this Mac…").font(.caption)
                        Spacer()
                        Button("Cancel") { assistant.cancel() }
                    } else if assistant.available {
                        Button("Ask On-Device AI", action: ask)
                            .disabled(query.count > 600)
                        if askedEmpty {
                            Text("Type a question first.").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    } else {
                        Text(assistant.availabilityMessage).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Check Availability") { assistant.refreshAvailability() }
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
            } header: {
                InfoHeader("Ask Battistics", text: assistant.availabilityMessage)
            }
            if !assistant.sources.isEmpty {
                Section("Source Articles") {
                    ForEach(assistant.sources) { article in ArticleTile(article: article) }
                }
            }
            Section("Built-in Answers") {
                if articles.isEmpty {
                    Text("No matching articles. Try battery, sleep, heat, history, or assistant.")
                        .foregroundStyle(.secondary)
                    Button("Show All Answers") { query = "" }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(articles) { article in ArticleTile(article: article) }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .modifier(TourScrollModifier())
        .task { assistant.refreshAvailability() }
        .onChange(of: scenePhase) { if scenePhase == .active { assistant.refreshAvailability() } }
        .onDisappear { assistant.cancel() }
    }

    private func ask() {
        guard !question.isEmpty else {
            askedEmpty = true
            fieldFocused = true
            return
        }
        assistant.ask(query)
    }
}

/// A question that opens its answer beside it, so the list stays one screen.
private struct ArticleTile: View {
    let article: HelpArticle
    @Environment(AppModel.self) private var model
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Text(article.title)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.fill.opacity(open ? 0.9 : 0.5), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(article.title).font(.headline)
                Text(article.answer)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open \(article.pane.title)") {
                    open = false
                    model.dashboardPane = article.pane
                }
            }
            .padding(16)
            .frame(width: 380, alignment: .leading)
        }
    }
}
