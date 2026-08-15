import Foundation
import Testing

@testable import BattisticsCore

@Suite("Sleep timer writes")
struct SleepTimerTests {
    @Test func eachTimerMapsToItsPmsetKey() {
        #expect(
            PowerSettingsWriter.arguments(for: .display, interval: .tenMinutes, source: .battery)
                == ["-b", "displaysleep", "10"])
        #expect(
            PowerSettingsWriter.arguments(for: .system, interval: .oneHour, source: .ac)
                == ["-c", "sleep", "60"])
        #expect(
            PowerSettingsWriter.arguments(for: .disk, interval: .never, source: .all)
                == ["-a", "disksleep", "0"])
    }

    @Test func intervalRawValueIsItsMinutesWithZeroMeaningNever() {
        #expect(SleepInterval.never.rawValue == 0)
        #expect(SleepInterval.threeHours.rawValue == 180)
        #expect(SleepInterval(rawValue: 15) == .fifteenMinutes)
        // A value set outside the app has no case, and must not be invented.
        #expect(SleepInterval(rawValue: 7) == nil)
    }

    @Test func intervalsAreOfferedShortestFirstAfterNever() {
        let all = SleepInterval.allCases
        #expect(all.first == .never)
        let timed = all.dropFirst().map(\.rawValue)
        #expect(timed == timed.sorted())
        #expect(timed == [1, 2, 3, 5, 10, 15, 30, 60, 120, 180])
    }

    /// The whole safety argument in one test: nothing crossing this boundary
    /// is free-form. Every argument is either one of three known flags or a
    /// non-negative integer, so no value can ever be read by pmset as an
    /// option, and none can be spliced into something else.
    @Test func noArgumentCanBeMistakenForAFlag() {
        var everything: [String] = []
        for timer in SleepTimer.allCases {
            for interval in SleepInterval.allCases {
                for source in PowerSource.allCases {
                    everything += PowerSettingsWriter.arguments(
                        for: timer, interval: interval, source: source)
                }
            }
        }
        for setting in LowPowerModeSetting.allCases {
            everything += PowerSettingsWriter.arguments(for: setting)
        }
        for mode in EnergyMode.allCases {
            everything += PowerSettingsWriter.arguments(for: mode)
        }

        let allowedFlags: Set<String> = ["-a", "-b", "-c"]
        for argument in everything where !allowedFlags.contains(argument) {
            #expect(!argument.hasPrefix("-"), "\(argument) could be parsed as an option")
            #expect(
                argument.allSatisfy { $0.isLetter || $0.isNumber },
                "\(argument) is not a bare token")
        }
    }

    /// The complete vocabulary a fully compromised client could ask for.
    @Test func theRootVocabularyIsSmallAndFullyEnumerable() {
        let sleepOperations =
            SleepTimer.allCases.count * SleepInterval.allCases.count * PowerSource.allCases.count
        let total = LowPowerModeSetting.allCases.count + EnergyMode.allCases.count + sleepOperations
        #expect(sleepOperations == 99)
        #expect(total == 106)
    }
}
