import SwiftUI

struct TourSpotlight: View {
    let focus: CGRect?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            Group {
                if reduceTransparency {
                    Color(nsColor: .windowBackgroundColor).opacity(0.2)
                } else {
                    WithinWindowBlur().opacity(0.5)
                }
            }
            .mask {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    if let focus { path.addRoundedRect(in: focus, cornerSize: CGSize(width: 8, height: 8)) }
                }
                .fill(style: FillStyle(eoFill: true))
            }
            if let focus {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: focus.width, height: focus.height)
                    .position(x: focus.midX, y: focus.midY)
            }
        }
        .accessibilityHidden(true)
    }
}

/// SwiftUI materials on macOS blur what is behind the window; the tour needs
/// the window's own content softened instead.
private struct WithinWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .withinWindow
        view.material = .popover
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
