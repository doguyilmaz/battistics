import Foundation
import Testing

@testable import BattisticsCore

@Suite("Status palette")
struct StatusPaletteTests {
    private let allRules = StatusColorRules(
        colorLow: true, lowThreshold: 20, colorHigh: true, colorCharging: true)

    // MARK: - Contrast

    /// WCAG 2.1 relative luminance.
    private func luminance(_ color: StatusPalette.RGB) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(color.red) + 0.7152 * channel(color.green)
            + 0.0722 * channel(color.blue)
    }

    private func contrastRatio(_ a: StatusPalette.RGB, _ b: StatusPalette.RGB) -> Double {
        let (first, second) = (luminance(a), luminance(b))
        let (lighter, darker) = first > second ? (first, second) : (second, first)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static let white = StatusPalette.RGB(red: 1, green: 1, blue: 1)
    private static let black = StatusPalette.RGB(red: 0, green: 0, blue: 0)

    @Test func greenAndBlueHoldUpOnEitherMenuBar() {
        // One fixed color has to survive both backdrops, since the menu bar is
        // translucent over whatever wallpaper is up. 3:1 is WCAG 1.4.11 for
        // graphical objects.
        for level in [BatteryStatusLevel.full, .charging] {
            let rgb = try! #require(StatusPalette.rgb(for: level))
            #expect(contrastRatio(rgb, Self.white) >= 3.0, "\(level) on a light menu bar")
            #expect(contrastRatio(rgb, Self.black) >= 3.0, "\(level) on a dark menu bar")
        }
    }

    @Test func greenIsDeepenedBecauseTheStockOneWashesOut() {
        let systemGreen = StatusPalette.RGB(red: 40 / 255, green: 205 / 255, blue: 65 / 255)
        let chosenGreen = try! #require(StatusPalette.rgb(for: .full))
        #expect(contrastRatio(systemGreen, Self.white) < 3.0)
        #expect(contrastRatio(chosenGreen, Self.white) > contrastRatio(systemGreen, Self.white))
    }

    /// Blue is left as it ships. Any brighter variant trades light-menu-bar
    /// contrast for dark, and the stock value already sits near the
    /// luminance that balances the two.
    @Test func blueIsUnchangedBecauseItAlreadyBalancesBothBackdrops() {
        let blue = try! #require(StatusPalette.rgb(for: .charging))
        #expect(blue == StatusPalette.RGB(red: 0, green: 122 / 255, blue: 1))
        #expect(contrastRatio(blue, Self.white) >= 4.0)
        #expect(contrastRatio(blue, Self.black) >= 4.0)
    }

    /// Orange is the stock system value and is kept deliberately. It is the
    /// one status color that does not clear 3:1 on a light menu bar; noted
    /// here so the shortfall is recorded rather than forgotten.
    @Test func orangeIsKnownWeakOnALightMenuBar() {
        let orange = try! #require(StatusPalette.rgb(for: .low))
        #expect(contrastRatio(orange, Self.white) < 3.0)
        #expect(contrastRatio(orange, Self.black) >= 3.0)
    }

    @Test func neutralHasNoColorSoItCanRenderAsATemplate() {
        #expect(StatusPalette.rgb(for: .neutral) == nil)
    }

    // MARK: - Level ladder

    @Test func chargingOutranksEveryOtherLevel() {
        #expect(
            StatusPalette.level(percent: 5, charging: true, external: true, rules: allRules)
                == .charging)
    }

    @Test func criticalOutranksLowOnBattery() {
        #expect(
            StatusPalette.level(percent: 10, charging: false, external: false, rules: allRules)
                == .critical)
        #expect(
            StatusPalette.level(percent: 11, charging: false, external: false, rules: allRules)
                == .low)
    }

    @Test func lowLevelsAreIgnoredWhilePluggedIn() {
        #expect(
            StatusPalette.level(percent: 5, charging: false, external: true, rules: allRules)
                == .neutral)
    }

    @Test func fullOnlyAppliesFromNinetyFive() {
        #expect(
            StatusPalette.level(percent: 95, charging: false, external: true, rules: allRules)
                == .full)
        #expect(
            StatusPalette.level(percent: 94, charging: false, external: true, rules: allRules)
                == .neutral)
    }

    @Test func everyRuleDisabledStaysNeutralSoTheIconMatchesTheMenuBar() {
        let none = StatusColorRules(
            colorLow: false, lowThreshold: 20, colorHigh: false, colorCharging: false)
        #expect(StatusPalette.level(percent: 3, charging: true, external: true, rules: none) == .neutral)
        #expect(StatusPalette.level(percent: 3, charging: false, external: false, rules: none) == .neutral)
        #expect(StatusPalette.level(percent: 100, charging: false, external: true, rules: none) == .neutral)
    }
}
