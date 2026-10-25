import SwiftUI

/// A form section title with its explanation behind an info button, so a
/// pane reads as controls rather than paragraphs.
struct InfoHeader: View {
    let title: LocalizedStringKey
    let paragraphs: [LocalizedStringKey]
    @State private var showing = false

    init(_ title: LocalizedStringKey, info paragraphs: LocalizedStringKey...) {
        self.title = title
        self.paragraphs = paragraphs
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Button {
                showing.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("About \(Text(title))"))
            .popover(isPresented: $showing, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(paragraphs.indices, id: \.self) { index in
                        Text(paragraphs[index])
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.callout)
                .padding(14)
                .frame(width: 300, alignment: .leading)
            }
        }
    }
}
