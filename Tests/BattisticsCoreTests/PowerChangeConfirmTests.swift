import Foundation
import Testing

@testable import BattisticsCore

@Suite("Power change confirmation")
struct PowerChangeConfirmTests {
    private func settings(batteryLPM: Bool, acLPM: Bool, display: Int) -> PowerSettings {
        var battery = PowerSettings.Source()
        battery.lowPowerMode = batteryLPM
        battery.displaySleepMinutes = display
        var ac = PowerSettings.Source()
        ac.lowPowerMode = acLPM
        ac.displaySleepMinutes = display
        return PowerSettings(ac: ac, battery: battery)
    }

    @Test func confirmsALowPowerChangeThatLanded() {
        let after = settings(batteryLPM: true, acLPM: false, display: 10)
        #expect(PowerChange.lowPowerMode(.onlyOnBattery).isReflected(in: after))
        #expect(!PowerChange.lowPowerMode(.always).isReflected(in: after))
    }

    @Test func confirmsASleepTimerPerSource() {
        let after = settings(batteryLPM: false, acLPM: false, display: 15)
        #expect(PowerChange.sleepTimer(.display, .fifteenMinutes, .battery).isReflected(in: after))
        #expect(!PowerChange.sleepTimer(.display, .tenMinutes, .battery).isReflected(in: after))
    }

    /// A read that failed entirely must not be mistaken for a change that
    /// worked, or a silent write failure would report success.
    @Test func missingSettingsNeverConfirm() {
        #expect(!PowerChange.lowPowerMode(.never).isReflected(in: nil))
        #expect(!PowerChange.sleepTimer(.disk, .never, .ac).isReflected(in: PowerSettings()))
    }

    /// Energy Mode is absent on most Macs; a change to it cannot be claimed
    /// to have landed when the machine cannot report one.
    @Test func absentEnergyModeNeverConfirms() {
        #expect(!PowerChange.energyMode(.high).isReflected(in: settings(batteryLPM: false, acLPM: false, display: 0)))
    }
}
