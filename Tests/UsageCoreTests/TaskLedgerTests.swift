import XCTest
@testable import UsageCore

final class TaskLedgerTests: XCTestCase {
    private func snapshot(id: String = UUID().uuidString, account: String = "hashed-account",
                         used: Double = 20, tokens: Double? = 1_000,
                         reset: Double? = 10_000, quotaHealth: SourceHealth = .fresh,
                         tokenHealth: SourceHealth = .fresh) -> AccountUsageSnapshot {
        AccountUsageSnapshot(id: id, capturedAt: 1_000, accountKey: account,
                             quotaObservedAt: 990, quotaHealth: quotaHealth,
                             quotaWindows: [ObservedQuotaWindow(id: "codex:primary", name: "Codex",
                                                                  usedPercent: used, windowDurationMins: 300,
                                                                  resetsAt: reset)],
                             accountTokenTotal: tokens, tokenObservedAt: 990, tokenHealth: tokenHealth)
    }

    func testTaskLifecycleAndSnapshotReferencesRoundTrip() throws {
        var ledger = TaskLedger()
        XCTAssertThrowsError(try ledger.finish(retries: 0, outcome: .accepted, validationNotes: nil,
                                               snapshotID: nil, now: 2_000))
        try ledger.start(title: "Fix login", project: "app", issue: "#42", model: "Codex model",
                         reasoning: "high", snapshotID: "start", now: 1_000)
        XCTAssertThrowsError(try ledger.start(title: "Second", project: nil, issue: nil, model: nil,
                                              reasoning: nil, snapshotID: nil, now: 1_001))
        XCTAssertThrowsError(try ledger.finish(retries: -1, outcome: .accepted, validationNotes: nil,
                                               snapshotID: nil, now: 2_000))
        try ledger.finish(retries: 3, outcome: .accepted, validationNotes: "Unit tests passed",
                          snapshotID: "end", now: 3_520)

        let task = try XCTUnwrap(ledger.records.first)
        XCTAssertNil(ledger.activeTask)
        XCTAssertEqual(task.durationSeconds, 2_520)
        XCTAssertEqual(task.project, "app")
        XCTAssertEqual(task.issue, "#42")
        XCTAssertEqual(task.retries, 3)
        XCTAssertEqual(task.outcome, .accepted)
        XCTAssertNil(task.attributedSessionTokens)

        let decoded = try JSONDecoder().decode(TaskLedger.self, from: JSONEncoder().encode(ledger))
        XCTAssertEqual(decoded, ledger)
        let observations = AccountObservationLedger()
        let package = TaskLedgerExport(exportedAt: 4_000, taskLedger: ledger, accountObservations: observations)
        XCTAssertEqual(try JSONDecoder().decode(TaskLedgerExport.self, from: JSONEncoder().encode(package)).taskLedger, ledger)
    }

    func testAccountQuotaAndTokenChangesRemainPeriodObservations() {
        let start = snapshot(used: 20, tokens: 1_000)
        let end = snapshot(used: 26, tokens: 1_250)
        XCTAssertEqual(observedQuotaChange(from: start, to: end, windowID: "codex:primary"), .change(6))
        XCTAssertEqual(observedTokenCounterChange(from: start, to: end), .change(250))
        XCTAssertEqual(observedQuotaChange(from: start, to: snapshot(account: "other"), windowID: "codex:primary"), .accountChanged)
        XCTAssertEqual(observedQuotaChange(from: start, to: snapshot(used: 5, reset: 20_000), windowID: "codex:primary"), .reset)
        XCTAssertEqual(observedQuotaChange(from: start, to: end, windowID: "missing"), .unavailable)
        XCTAssertEqual(observedTokenCounterChange(from: start, to: snapshot(tokens: 10)), .reset)
        XCTAssertEqual(observedQuotaChange(from: snapshot(quotaHealth: .stale), to: end, windowID: "codex:primary"), .unavailable)
        XCTAssertEqual(observedTokenCounterChange(from: start, to: snapshot(tokens: 1_250, tokenHealth: .stale)), .unavailable)
    }

    func testSnapshotsAreStoredSeparatelyFromTaskRecords() throws {
        var ledger = TaskLedger()
        var observations = AccountObservationLedger()
        let before = snapshot(id: "before")
        let after = snapshot(id: "after", used: 24, tokens: 1_200)
        observations.append(before)
        observations.append(after)
        try ledger.start(title: "Review PR", project: "widget", issue: "PR #7", model: "Codex",
                         reasoning: "medium", snapshotID: before.id, now: 1_000)
        try ledger.finish(retries: 1, outcome: .needsWork, validationNotes: "One test fails",
                          snapshotID: after.id, now: 2_000)
        let start = observations.snapshot(id: ledger.records[0].startSnapshotID)
        let end = observations.snapshot(id: ledger.records[0].endSnapshotID)
        XCTAssertEqual(observedQuotaChange(from: start, to: end, windowID: "codex:primary"), .change(4))
        XCTAssertEqual(observedTokenCounterChange(from: start, to: end), .change(200))
        XCTAssertNil(ledger.records[0].attributedSessionTokens)
    }

    func testSourceDiagnosticSerializationIncludesFreshnessAndErrorSeparately() throws {
        let diagnostic = SourceDiagnostic(id: "codex.quota", health: .fresh,
                                          lastAttemptAt: 100, lastSuccessAt: 99, ageSeconds: 1,
                                          staleAfterSeconds: 90, lastErrorCode: "timeout",
                                          consecutiveFailures: 1, nextAttemptAt: 120)
        let decoded = try JSONDecoder().decode(SourceDiagnostic.self, from: JSONEncoder().encode(diagnostic))
        XCTAssertEqual(decoded, diagnostic)
        XCTAssertEqual(decoded.health, .fresh)
        XCTAssertEqual(decoded.lastErrorCode, "timeout")
    }

    func testFreshnessUsesLastSuccessAndKeepsRecentAttemptErrorsSeparate() {
        XCTAssertEqual(sourceHealth(lastSuccessAt: 95, now: 100, staleAfterSeconds: 10, errorCode: "timeout"), .fresh)
        XCTAssertEqual(sourceHealth(lastSuccessAt: 80, now: 100, staleAfterSeconds: 10), .stale)
        XCTAssertEqual(sourceHealth(lastSuccessAt: nil, now: 100, staleAfterSeconds: 10, errorCode: "timeout"), .error)
        XCTAssertEqual(sourceHealth(lastSuccessAt: nil, now: 100, staleAfterSeconds: 10), .unavailable)
        XCTAssertEqual(sourceHealth(lastSuccessAt: 95, now: 100, staleAfterSeconds: 10, enabled: false, paused: true), .disabled)
        XCTAssertEqual(sourceHealth(lastSuccessAt: 95, now: 100, staleAfterSeconds: 10, paused: true), .paused)
    }
}
