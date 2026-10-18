import SwiftUI

struct TourScrollModifier: ViewModifier {
    @Environment(\.tourStep) private var step

    func body(content: Content) -> some View {
        ScrollViewReader { scroll in
            content.onChange(of: step, initial: true) {
                if let step { scroll.scrollTo(step, anchor: .top) }
            }
        }
    }
}
