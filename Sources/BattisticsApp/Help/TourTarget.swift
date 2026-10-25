import SwiftUI

extension EnvironmentValues {
    @Entry var tourStep: TourStep? = nil
}

struct TourTargetPreference: PreferenceKey {
    static var defaultValue: [TourStep: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [TourStep: Anchor<CGRect>], nextValue: () -> [TourStep: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

/// Scrolls the current step's target into view.
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

extension View {
    func tourTarget(_ step: TourStep) -> some View {
        id(step).anchorPreference(key: TourTargetPreference.self, value: .bounds) { [step: $0] }
    }
}
