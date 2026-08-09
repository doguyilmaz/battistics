import SwiftUI

/// Card background: Liquid Glass on macOS 26, material with a hairline
/// border before it. The only place in the app that branches on OS version
/// for chrome, so views stay clean.
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = 12
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { GlassBackground(cornerRadius: cornerRadius) }
    }
}

struct GlassBackground: View {
    var cornerRadius: CGFloat = 12

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.quaternary, lineWidth: 1)
                }
        }
    }
}

/// Ring gauge used for the Charge / Health hero pair.
struct GaugeRing: View {
    let value: Double
    let title: String
    let color: Color
    var symbol: String?
    var diameter: CGFloat = 92

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.16), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(max(value / 100, 0), 1))
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.65), color],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * value / 100)),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: value)
                VStack(spacing: 0) {
                    if let symbol {
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    Text("\(Int(value.rounded()))%")
                        .font(.system(size: 21, weight: .semibold, design: .rounded))
                        .contentTransition(.numericText())
                }
            }
            .frame(width: diameter, height: diameter)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// One label/value line inside a stat card.
struct StatRow: View {
    let label: String
    let value: String
    var valueColor: Color?

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(valueColor ?? .primary)
                .monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

/// Section title with an optional "?" popover explaining every stat in
/// plain language.
struct SectionHeader: View {
    let title: String
    var help: [(term: String, explanation: String)] = []

    @State private var showingHelp = false

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.6)
            Spacer()
            if !help.isEmpty {
                Button {
                    showingHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingHelp, arrowEdge: .trailing) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(help, id: \.term) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.term).font(.caption.weight(.semibold))
                                Text(entry.explanation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding(14)
                    .frame(width: 280)
                }
            }
        }
    }
}

extension Color {
    /// Charge level color ramp shared by gauges and charts.
    static func charge(percent: Double) -> Color {
        switch percent {
        case ..<10: .red
        case ..<20: .orange
        default: .green
        }
    }

    static func health(percent: Double) -> Color {
        switch percent {
        case 80...: .green
        case 60..<80: .orange
        default: .red
        }
    }
}
