import SwiftUI

struct TourTargetPreference: PreferenceKey {
    static var defaultValue: [TourStep: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [TourStep: Anchor<CGRect>], nextValue: () -> [TourStep: Anchor<CGRect>]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}
