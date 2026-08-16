import Testing

@testable import BattisticsCore

@Suite("Temperature unit")
struct TemperatureUnitTests {
    /// A scale has one unit. `both` is a text convenience — "35.0°C / 95.0°F"
    /// reads fine in a row and cannot be an axis — so a chart resolves it to
    /// the unit readings are stored in rather than picking arbitrarily.
    @Test func bothResolvesToCelsiusForAScale() {
        #expect(TemperatureUnit.both.forScale == .celsius)
        #expect(TemperatureUnit.celsius.forScale == .celsius)
        #expect(TemperatureUnit.fahrenheit.forScale == .fahrenheit)
    }

    @Test func onlyFahrenheitConverts() {
        #expect(TemperatureUnit.celsius.convert(35) == 35)
        #expect(TemperatureUnit.both.convert(35) == 35)
        #expect(TemperatureUnit.fahrenheit.convert(35) == 95)
        #expect(TemperatureUnit.fahrenheit.convert(0) == 32)
    }

    /// The chart labels an already-converted value, so its symbol has to come
    /// from the same unit the points were converted with. Reading the
    /// preference separately is what let a Celsius series claim to be
    /// Fahrenheit.
    @Test func symbolMatchesTheConversion() {
        for unit in TemperatureUnit.allCases {
            let scale = unit.forScale
            let converted = scale.convert(35)
            #expect((converted == 95) == (scale.symbol == "°F"))
        }
    }

    /// Formatting still takes Celsius and converts internally; the new helpers
    /// must not have changed what existing callers see.
    @Test func textFormattingIsUnchanged() {
        #expect(Formatting.temperature(35, unit: .celsius) == "35.0°C")
        #expect(Formatting.temperature(35, unit: .fahrenheit) == "95.0°F")
        #expect(Formatting.temperature(35, unit: .both) == "35.0°C / 95.0°F")
    }
}
