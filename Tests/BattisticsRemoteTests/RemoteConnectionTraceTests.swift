import CloudKit
import Foundation
import Testing
@testable import BattisticsRemote

@Suite("Local connection diagnostics")
struct RemoteConnectionTraceTests {
    @Test func reportsErrorCodesButNeverErrorDescriptionsOrUserInfo() {
        let trace = RemoteConnectionTrace()
        let error = NSError(domain: "CKErrorDomain", code: 9, userInfo: [
            NSLocalizedDescriptionKey: "private-person@example.test at Private Mac",
            "token": "secret-token-do-not-copy", "record": "private-record-id"
        ])
        trace.record(.failed(error), phase: .query, id: "ABCDEF12")
        let report = trace.report()
        #expect(report.contains("query"))
        #expect(report.contains("CKErrorDomain/9"))
        for privateValue in ["private-person", "Private Mac", "secret-token", "private-record-id", "example.test"] {
            #expect(!report.contains(privateValue))
        }
    }

    @Test func traceIsBounded() {
        let trace = RemoteConnectionTrace()
        for i in 0..<30 { trace.record(.started, phase: .query, id: "req\(i)") }
        let report = trace.report()
        #expect(report.split(separator: "\n").filter { $0.contains("query") }.count == 20)
        #expect(report.hasPrefix("clock="))
        #expect(report.contains("req29"))
        #expect(!report.contains("req0 "))
    }

    @Test func deadlinesAndCancellationAreNotMislabelledAsFrameworkErrors() {
        let trace = RemoteConnectionTrace()
        trace.record(.failed(RemoteDeadline.Failure.exceeded), phase: .zoneSetup, id: "deadline")
        trace.record(.failed(CancellationError()), phase: .recordRead, id: "cancel")
        #expect(trace.report().contains("failed deadline"))
        #expect(trace.report().contains("failed cancelled"))
    }

    @Test func copyingAReportDoesNotStartACloudKitRequest() async {
        let cloud = RemoteCloud(operations: .init { _ in
            Issue.record("Diagnostics must not submit an operation")
        })
        let report = await cloud.connectionReport()
        #expect(report.contains("sync=query2"))
        #expect(report.contains("prepared=false"))
    }

    @Test func itemCompletionIsVisibleEvenIfAggregateCompletionNeverArrives() async throws {
        let submitted = CloudKitBuffer<CKModifyRecordZonesOperation?>(nil)
        let operations = CloudKitOperations { operation in
            guard let zone = operation as? CKModifyRecordZonesOperation else { return }
            submitted.update { $0 = zone }
            zone.perRecordZoneSaveBlock?(RemoteCloud.zoneID, .success(CKRecordZone(zoneID: RemoteCloud.zoneID)))
            // Deliberately do not invoke operation-wide completion yet.
        }
        await #expect(throws: RemoteDeadline.Failure.self) {
            try await operations.createZone(until: .now.advanced(by: .milliseconds(60)))
        }
        let report = operations.connectionReport()
        #expect(report.contains("zone-setup"))
        #expect(report.contains("item-ready"))
        #expect(report.contains("failed deadline"))
        let operation = try #require(submitted.read())
        operation.modifyRecordZonesResultBlock?(.failure(CKError(.operationCancelled)))
    }
}
