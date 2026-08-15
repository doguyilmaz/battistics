import Foundation
import Testing

@testable import BattisticsCore

@Suite("Power settings writer")
struct PowerSettingsWriterTests {
    /// `-b` is battery, `-c` is the power adapter. The four-way choice maps
    /// onto the two flags macOS actually stores.
    @Test func lowPowerModeMapsOntoBothSourceFlags() {
        #expect(
            PowerSettingsWriter.arguments(for: .never)
                == ["-b", "lowpowermode", "0", "-c", "lowpowermode", "0"])
        #expect(
            PowerSettingsWriter.arguments(for: .always)
                == ["-b", "lowpowermode", "1", "-c", "lowpowermode", "1"])
        #expect(
            PowerSettingsWriter.arguments(for: .onlyOnBattery)
                == ["-b", "lowpowermode", "1", "-c", "lowpowermode", "0"])
        #expect(
            PowerSettingsWriter.arguments(for: .onlyOnPowerAdapter)
                == ["-b", "lowpowermode", "0", "-c", "lowpowermode", "1"])
    }

    @Test func energyModeAppliesToEverySource() {
        #expect(PowerSettingsWriter.arguments(for: EnergyMode.automatic) == ["-a", "powermode", "0"])
        #expect(PowerSettingsWriter.arguments(for: EnergyMode.low) == ["-a", "powermode", "1"])
        #expect(PowerSettingsWriter.arguments(for: EnergyMode.high) == ["-a", "powermode", "2"])
    }

    /// The command is assembled from fixed enum cases, never from anything a
    /// user typed, and this is what keeps it safe to hand to a shell.
    @Test func everyArgumentIsAFixedTokenWithNothingToEscape() {
        var all = PowerSettingsWriter.arguments(for: LowPowerModeSetting.onlyOnBattery)
        all += PowerSettingsWriter.arguments(for: EnergyMode.high)
        for argument in all {
            #expect(argument.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
        }
    }

    @Test func theCommandIsAbsolutePathed() {
        let command = PowerSettingsWriter.command(
            PowerSettingsWriter.arguments(for: LowPowerModeSetting.always))
        #expect(command == "/usr/bin/pmset -b lowpowermode 1 -c lowpowermode 1")
    }
}
