import SwiftUI

struct TourSpotlight: View {
    let focus: CGRect?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                path.addRect(CGRect(origin: .zero, size: geometry.size))
                if let focus { path.addRoundedRect(in: focus, cornerSize: CGSize(width: 8, height: 8)) }
            }
            .fill(.black.opacity(reduceTransparency ? 0.8 : 0.6), style: FillStyle(eoFill: true))
            if let focus {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                    .frame(width: focus.width, height: focus.height)
                    .position(x: focus.midX, y: focus.midY)
            }
        }
        .accessibilityHidden(true)
    }
}
