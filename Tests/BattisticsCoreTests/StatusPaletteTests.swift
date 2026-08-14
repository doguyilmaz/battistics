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

    @Test func everyStatusColorClearsTheNonTextContrastFloorOnBothMenuBars() {
        // WCAG 1.4.11 asks 3:1 for graphical objects. The menu bar is
        // translucent over an arbitrary wallpaper, so anything lower is
        // illegible on some desktops.
        for level in BatteryStatusLevel.allCases where level != .neutral {
            let light = try! #require(StatusPalette.rgb(for: level, dark: false))
            #expect(
                contrastRatio(light, Self.white) >= 3.0,
                "\(level) on a light menu bar")

            let dark = try! #require(StatusPalette.rgb(for: level, dark: true))
            #expect(
                contrastRatio(dark, Self.black) >= 3.0,
                "\(level) on a dark menu bar")
        }
    }

    @Test func theSystemColorsThisPaletteReplacesWouldHaveFailed() {
        // Guards the reason the palette exists: NSColor.systemGreen and
        // .systemOrange are mid-luminance and wash out on a light menu bar.
        let systemGreen = StatusPalette.RGB(red: 40 / 255, green: 205 / 255, blue: 65 / 255)
        let systemOrange = StatusPalette.RGB(red: 1, green: 149 / 255, blue: 0)
        #expect(contrastRatio(systemGreen, Self.white) < 3.0)
        #expect(contrastRatio(systemOrange, Self.white) < 3.0)
    }

    @Test func neutralHasNoColorSoItCanRenderAsATemplate() {
        #expect(StatusPalette.rgb(for: .neutral, dark: false) == nil)
        #expect(StatusPalette.rgb(for: .neutral, dark: true) == nil)
    }

    // MARK: - Level ladder

    @Test func chargingOutranksEveryOtherLevel() {
        let level = StatusPalette.level(
            percent: 5, charging: true, external: true, rules: allRules)
        #expect(level == .charging)
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
