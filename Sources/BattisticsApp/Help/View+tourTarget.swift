import SwiftUI

extension View {
    @ViewBuilder
    func tourTarget(_ step: TourStep?) -> some View {
        if let step {
            self.id(step).anchorPreference(key: TourTargetPreference.self, value: .bounds) { [step: $0] }
        } else {
            self
        }
    }
}
