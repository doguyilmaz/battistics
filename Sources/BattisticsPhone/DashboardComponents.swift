import BattisticsRemote
import SwiftUI

extension View {
    func card(border: Color? = nil) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground).opacity(0.9), in: .rect(cornerRadius: 22))
            .overlay {
                if let border {
                    RoundedRectangle(cornerRadius: 22).strokeBorder(border, lineWidth: 1)
                }
            }
    }

    /// iOS 27 draws a hard line under the navigation bar, and its soft edge
    /// drops the blur. This keeps the soft edge and puts back a blur that
    /// fades out, like iOS 26.
    @ViewBuilder
    func softScrollEdge() -> some View {
        if #available(iOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }

    /// Goes on a scroll view or list, below the bar's buttons. The bar's height
    /// comes from outside the scroll view, which does not report it.
    func topBlur() -> some View {
        GeometryReader { proxy in
            topBlur(height: proxy.safeAreaInsets.top)
        }
    }

    private func topBlur(height: CGFloat) -> some View {
        overlay(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.7),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .frame(height: height)
                .offset(y: -height)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// iOS has no public link to Personal Hotspot settings, so this explains the path instead.
    func hotspotHelp(isPresented: Binding<Bool>) -> some View {
        alert("Turn On Personal Hotspot", isPresented: isPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("On this iPhone, open Settings › Personal Hotspot and turn on Allow Others to Join. A Mac set to join hotspots automatically connects by itself.")
        }
    }
}

/// The scrolling page every dashboard sits on.
struct DashboardPage<Content: View>: View {
    var glow: Glow?
    /// Stretches the content to the screen's height, for pages short enough to fit.
    var fills = false
    var refresh: (() async -> Void)?
    @ViewBuilder var content: Content
    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 12) { content }
                .frame(minHeight: fills ? max(visibleHeight - 16, 0) : nil, alignment: .top)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
        .scrollIndicators(.hidden)
        .topBlur()
        .background {
            ZStack(alignment: .top) {
                Color(.systemGroupedBackground)
                if let glow { AmbientGlow(glow: glow) }
            }
            .ignoresSafeArea()
        }
        .refreshable { await refresh?() }
    }
}

/// The two colors of the light behind the top of a dashboard: the battery on
/// the left, what the device is doing on the right.
struct Glow: Equatable {
    var battery: Color
    var activity: Color

    static let offline = Glow(battery: .gray, activity: .gray)

    init(battery: Color, activity: Color? = nil) {
        self.battery = battery
        self.activity = activity ?? battery
    }

    init(_ status: RemoteStatus, reachable: Bool) {
        guard reachable else { self = .offline; return }
        let battery = status.battery.map(PowerPalette.batteryTint) ?? .accentColor
        let activity: Color? = status.session != nil ? .orange : (status.network == .hotspot ? PowerPalette.hotspot : nil)
        self.init(battery: battery, activity: activity)
    }
}

private struct AmbientGlow: View {
    let glow: Glow
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                Ellipse().fill(glow.battery).offset(x: -width * 0.25)
                Ellipse().fill(glow.activity).offset(x: width * 0.25)
            }
            .frame(width: width * 1.1, height: 240)
            .offset(x: -width * 0.05, y: -140)
            .blur(radius: 60)
            .opacity(scheme == .dark ? 0.5 : 0.28)
        }
        .animation(.easeInOut(duration: 0.9), value: glow)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A two-line fact in the conditions grid.
struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    var tint: Color = .accentColor
    var highlighted = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                    .minimumScaleFactor(0.7)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            highlighted ? tint.opacity(0.10) : Color(.secondarySystemGroupedBackground),
            in: .rect(cornerRadius: 18)
        )
        .overlay {
            if highlighted { RoundedRectangle(cornerRadius: 18).strokeBorder(tint.opacity(0.4), lineWidth: 1) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small value with its label, three to a row under a battery headline.
struct MetricPill: View {
    let label: String
    let value: String
    var symbol: String?
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

struct BatteryGauge: View {
    let percent: Int?
    let symbol: String
    let tint: Color
    var charging = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Gauge(value: Double(percent ?? 0), in: 0...100) {
            Image(systemName: symbol).foregroundStyle(tint)
        } currentValueLabel: {
            Text(percent.map(String.init) ?? "–")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .contentTransition(.numericText(value: Double(percent ?? 0)))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(tint)
        .scaleEffect(1.2)
        .frame(width: 64, height: 64)
        .background {
            if animatesCharging {
                PhaseAnimator([0.16, 0.34]) { opacity in
                    Circle().fill(tint.opacity(opacity)).blur(radius: 12)
                } animation: { _ in .easeInOut(duration: 1.3) }
                .frame(width: 76, height: 76)
                .transition(.opacity)
            }
        }
        .overlay {
            if animatesCharging {
                ChargingParticles(tint: tint)
                    .frame(width: 96, height: 96)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: charging)
        .animation(.snappy, value: tint)
        .accessibilityLabel(Text("Battery"))
        .accessibilityValue(Text(percent.map { $0.percentText } ?? "–"))
    }

    private var animatesCharging: Bool {
        charging && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}

/// Sparks that come up from under the gauge and spiral along its ring to the
/// top while the battery charges.
private struct ChargingParticles: View {
    let tint: Color
    private static let count = 16

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            Canvas { canvas, size in
                let time = context.date.timeIntervalSinceReferenceDate
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for index in 0..<Self.count {
                    let seed = Double(index) / Double(Self.count)
                    let progress = (time * (0.38 + 0.22 * seed) + seed * 5.3).truncatingRemainder(dividingBy: 1)
                    let side: Double = index.isMultiple(of: 2) ? 1 : -1
                    // From straight below the ring, around one side, toward the top.
                    let angle = .pi / 2 - side * progress * (.pi * 0.92)
                    let radius = 45 - 9 * progress
                    let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                    let dot = 1.2 + 1.8 * sin(progress * .pi)
                    canvas.opacity = sin(progress * .pi) * 0.85
                    canvas.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)),
                                with: .color(tint))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
