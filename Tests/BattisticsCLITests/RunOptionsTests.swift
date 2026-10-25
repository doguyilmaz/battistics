import Foundation
import Testing
@testable import BattisticsCLI
import BattisticsCore

struct RunOptionsTests {
    @Test func defaultsDoNotExposeCommandArguments() throws {
        let options = try RunOptions(arguments: ["run", "--", "/usr/bin/tool", "secret", "$(touch nope)"])
        #expect(options.request.name == "tool")
        #expect(options.request.durationMinutes == 720)
        #expect(options.request.mode == "displayMaySleep")
        #expect(options.request.source == .command)
        #expect(options.command == ["/usr/bin/tool", "secret", "$(touch nope)"])
    }

    @Test func explicitOptionsAndChildFlagsStaySeparate() throws {
        let options = try RunOptions(arguments: ["run", "--name", "Build", "--mode", "displayOn", "--minutes", "60", "--", "swift", "--help"])
        #expect(options.request.validatedStart()?.name == "Build")
        #expect(options.request.validatedStart()?.duration == .oneHour)
        #expect(options.command == ["swift", "--help"])
    }

    @Test func rejectsUnboundedInvalidAndAmbiguousInput() {
        for arguments in [[], ["run"], ["run", "--"], ["run", "--", ""],
                          ["run", "--minutes", "0", "--", "true"],
                          ["run", "--minutes", "999", "--", "true"],
                          ["run", "--minutes", "60", "--minutes", "120", "--", "true"],
                          ["run", "--mode", "bad", "--", "true"],
                          ["run", "--name", "\n", "--", "true"],
                          ["run", "--other", "value", "--", "true"],
                          ["run", "--", "true", "\0"]] {
            #expect(throws: RunOptions.Failure.self) { try RunOptions(arguments: arguments) }
        }
    }

    @Test func oldIPCRequestsStillDecodeWithoutSource() throws {
        let request = try JSONDecoder().decode(AutomationRequest.self, from:
            Data(#"{"version":1,"operation":"start","name":"AI task","durationMinutes":60}"#.utf8))
        #expect(request.source == nil)
        #expect(request.validatedStart() != nil)
    }
}
