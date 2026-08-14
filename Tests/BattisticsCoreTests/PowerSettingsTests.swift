import Foundation
import Testing

@testable import BattisticsCore

@Suite("Power settings")
struct PowerSettingsTests {
    /// Verbatim `pmset -g custom` from an M-series MacBook.
    private let laptop = """
        Battery Power:
         Sleep On Power Button 1
         lowpowermode         1
         standby              1
         ttyskeepawake        1
         hibernatemode        3
         powernap             1
         hibernatefile        /var/vm/sleepimage
         displaysleep         0
         womp                 0
         networkoversleep     0
         sleep                1
         lessbright           1
         tcpkeepalive         1
         disksleep            10
        AC Power:
         Sleep On Power Button 1
         lowpowermode         0
         standby              1
         ttyskeepawake        1
         hibernatemode        3
         powernap             1
         hibernatefile        /var/vm/sleepimage
         displaysleep         0
         womp                 1
         networkoversleep     0
         sleep                1
         tcpkeepalive         1
         disksleep            10
        """

    @Test func bothPowerSourcesAreParsed() {
        let settings = PowerSettingsReader.parse(laptop)
        let battery = try! #require(settings.battery)
        let ac = try! #require(settings.ac)
        #expect(battery.lowPowerMode == true)
        #expect(ac.lowPowerMode == false)
        #expect(battery.diskSleepMinutes == 10)
        #expect(battery.displaySleepMinutes == 0)
        #expect(battery.systemSleepMinutes == 1)
    }

    /// Keys are multi-word; only the last token is the value.
    @Test func multiWordKeysParse() {
        let settings = PowerSettingsReader.parse(laptop)
        #expect(settings.battery?.sleepOnPowerButton == true)
        #expect(settings.ac?.wakeOnNetwork == true)
        #expect(settings.battery?.wakeOnNetwork == false)
    }

    /// macOS presents the two lowpowermode flags as one four-way choice, and
    /// this is the wording System Settings uses.
    @Test func lowPowerModeCollapsesToWhatSystemSettingsShows() {
        #expect(PowerSettingsReader.parse(laptop).lowPowerMode == .onlyOnBattery)

        func summary(battery: Int, ac: Int) -> LowPowerModeSetting? {
            PowerSettingsReader.parse(
                """
                Battery Power:
                 lowpowermode         \(battery)
                AC Power:
                 lowpowermode         \(ac)
                """
            ).lowPowerMode
        }
        #expect(summary(battery: 0, ac: 0) == .never)
        #expect(summary(battery: 1, ac: 1) == .always)
        #expect(summary(battery: 1, ac: 0) == .onlyOnBattery)
        #expect(summary(battery: 0, ac: 1) == .onlyOnPowerAdapter)
    }

    /// Energy Mode is a MacBook Pro / Max feature; the key is simply absent
    /// elsewhere and the row must stay hidden rather than claim a default.
    @Test func energyModeIsAbsentOnMachinesThatLackIt() {
        #expect(PowerSettingsReader.parse(laptop).energyMode == nil)
    }

    @Test func energyModeIsReadWhenPresent() {
        let pro = """
            AC Power:
             powermode            2
             sleep                10
            """
        #expect(PowerSettingsReader.parse(pro).energyMode == .high)
    }

    @Test func desktopsReportOnlyACPower() {
        let desktop = """
            AC Power:
             sleep                10
             displaysleep         15
            """
        let settings = PowerSettingsReader.parse(desktop)
        #expect(settings.battery == nil)
        #expect(settings.ac?.displaySleepMinutes == 15)
        // No battery half means the four-way summary cannot be formed.
        #expect(settings.lowPowerMode == nil)
    }

    @Test func garbageParsesToNothingRatherThanWrongValues() {
        let settings = PowerSettingsReader.parse("not pmset output at all")
        #expect(settings.ac == nil)
        #expect(settings.battery == nil)
        #expect(settings.lowPowerMode == nil)
    }
}
