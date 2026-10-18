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
                    Rectangle().fill(.ultraThinMaterial).opacity(0.35)
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
