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

/// Ring gauge used for the Charge / Health hero pair, and for the Cycles
/// ring on Overview.
struct GaugeRing: View {
    /// 0...100, drives the arc.
    let value: Double
    let title: String
    let color: Color
    var symbol: String?
    /// Overrides the centred number where the arc's fraction is not the
    /// figure the user wants: cycles show a count, not a percentage.
    var valueText: String?
    /// Small line under the number, e.g. the cycle limit.
    var subvalue: String?
    /// Mirrors `symbol` on the other side. The top slot is the charging
    /// bolt's, so a second state has to live at the bottom.
    var bottomSymbol: String?
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
                // The number sits dead centre in every ring; the bolt and
                // the limit float over it instead of joining a stack. In a
                // stack they push the number off centre, so a charging ring
                // stops lining up with the ones beside it. Offsets are fixed
                // because the number's size is, whatever the diameter.
                Text(valueText ?? "\(Int(value.rounded()))%")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                        .offset(y: -20)
                }
                if let subvalue {
                    Text(subvalue)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .offset(y: 19)
                }
                if let bottomSymbol {
                    Image(systemName: bottomSymbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(color)
                        .offset(y: 19)
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
    /// Goes in the gap the header already leaves, so a section can say it has
    /// nothing to show without becoming a row and changing its own height.
    var badge: String?
    var help: [(term: String, explanation: String)] = []

    @State private var showingHelp = false

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.6)
            Spacer()
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
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

/// Applies NSWindow-level behavior SwiftUI does not expose (float on top).
struct WindowLevelConfigurator: NSViewRepresentable {
    var keepOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            apply(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        apply(to: nsView.window)
    }

    private func apply(to window: NSWindow?) {
        window?.level = keepOnTop ? .floating : .normal
    }
}

extension Color {
    /// Low Power Mode. Yellow because that is what macOS uses for it, but a
    /// deeper gold than `.yellow`: system yellow is near-white in luminance
    /// (1.5:1 against a light background) and reads as a highlighter on an
    /// 8pt ring rather than as a status.
    static let lowPower = Color(red: 234 / 255, green: 179 / 255, blue: 8 / 255)

    /// Charge level color ramp shared by gauges and charts.
    ///
    /// Low Power Mode tints the ring yellow, which is the colour macOS uses
    /// for it — but only above the low-battery threshold. A warning outranks
    /// a mode: at 8% the ring stays red, because "you are about to run out"
    /// matters more than "you are in Low Power Mode".
    static func charge(percent: Double, lowPower: Bool = false) -> Color {
        switch percent {
        case ..<10: .red
        case ..<20: .orange
        default: lowPower ? .lowPower : .green
        }
    }

    static func health(percent: Double) -> Color {
        switch percent {
        case 80...: .green
        case 60..<80: .orange
        default: .red
        }
    }

    /// Cycles consumed against the pack's design limit.
    static func cycles(fraction: Double) -> Color {
        switch fraction {
        case ..<0.6: .green
        case ..<0.85: .orange
        default: .red
        }
    }
}
