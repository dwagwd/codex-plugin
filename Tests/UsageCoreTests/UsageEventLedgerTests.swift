import XCTest
@testable import UsageCore

final class UsageEventLedgerTests: XCTestCase {
    private func observation(_ time: Double, account: String = "account-A",
                             used: Double? = 20, reset: Double? = 5_000,
                             duration: Int? = 300, tokens: Double? = 1_000,
                             windows: [UsageLedgerWindow]? = nil,
                             tokenHealth: SourceHealth = .fresh,
                             tokenError: String? = nil) -> UsageLedgerObservation {
        UsageLedgerObservation(capturedAt: time, accountKey: account,
                              quotaWindows: windows ?? [UsageLedgerWindow(id: "codex:primary", name: "Codex",
                                                                          usedPercent: used,
                                                                          windowDurationMins: duration,
                                                                          resetsAt: reset)],
                              quotaHealth: .fresh, accountTokenTotal: tokens,
                              tokenObservedAt: tokens == nil ? nil : time,
                              tokenHealth: tokenHealth, tokenErrorCode: tokenError)
    }

    func testPeriodicCheckpointsUseLatestPollAndPreserveGap() {
        var ledger = UsageEventLedger()
        let first = ledger.observe(observation(1_000))
        XCTAssertEqual(first.map(\.kind), [.checkpoint])
        XCTAssertTrue(ledger.observe(observation(1_060, used: 21, tokens: 1_020)).isEmpty)
        let resumed = ledger.observe(observation(1_361, used: 22, tokens: 1_050))
        let gap = resumed.first { $0.kind == .dataGap }
        XCTAssertEqual(gap?.previousAt, 1_060)
        XCTAssertEqual(gap?.gapSeconds, 301)
        XCTAssertTrue(resumed.contains { $0.kind == .checkpoint })
        XCTAssertEqual(ledger.state.latestObservation?.capturedAt, 1_361)
    }

    func testCheckpointCarriesComparableAccountDeltaButGapBreaksComparison() {
        var ledger = UsageEventLedger()
        _ = ledger.observe(observation(1_000, used: 20, tokens: 1_000))
        _ = ledger.observe(observation(1_250, used: 21, tokens: 1_050))
        _ = ledger.observe(observation(1_500, used: 22, tokens: 1_100))
        _ = ledger.observe(observation(1_750, used: 23, tokens: 1_150))
        let checkpoint = ledger.observe(observation(1_900, used: 24, tokens: 1_200))
            .first { $0.kind == .checkpoint }
        XCTAssertEqual(checkpoint?.previousObservation?.quotaWindows.first?.usedPercent, 20)
        XCTAssertEqual(checkpoint?.observation?.quotaWindows.first?.usedPercent, 24)
        XCTAssertEqual(checkpoint?.previousObservation?.accountTokenTotal, 1_000)

        let afterGap = ledger.observe(observation(2_301, used: 26, tokens: 1_250))
            .first { $0.kind == .checkpoint }
        XCTAssertTrue(ledger.recentEvents.contains { $0.kind == .dataGap })
        XCTAssertNil(afterGap?.previousObservation)
    }

    func testAccountSwitchDoesNotCompareQuotaOrTokenTotalsAcrossAccounts() {
        var ledger = UsageEventLedger()
        _ = ledger.observe(observation(1_000, used: 80, tokens: 80_000))
        let events = ledger.observe(observation(1_060, account: "account-B", used: 5,
                                                reset: 9_000, tokens: 3))
        XCTAssertTrue(events.contains { $0.kind == .accountSwitch })
        XCTAssertFalse(events.contains { $0.kind == .windowReset || $0.kind == .sourceCorrection })
        XCTAssertEqual(events.first(where: { $0.kind == .accountSwitch })?.previousAccountKey, "account-A")
        XCTAssertEqual(events.first(where: { $0.kind == .accountSwitch })?.accountKey, "account-B")
        XCTAssertNil(events.first(where: { $0.kind == .checkpoint })?.previousObservation)
    }

    func testResetAndSourceCorrectionAreSeparateEvents() {
        var ledger = UsageEventLedger()
        _ = ledger.observe(observation(1_000, used: 20, reset: 5_000, tokens: 1_000))
        let reset = ledger.observe(observation(1_060, used: 5, reset: 6_000, tokens: 1_100))
        XCTAssertTrue(reset.contains { $0.kind == .windowReset && $0.windowID == "codex:primary" })

        let correction = ledger.observe(observation(1_120, used: 4, reset: 6_000, tokens: 900))
        XCTAssertTrue(correction.contains { $0.kind == .sourceCorrection && $0.sourceID == "codex.quota" })
        XCTAssertTrue(correction.contains { $0.kind == .sourceCorrection && $0.sourceID == "codex.accountTokens" })
    }

    func testMissingWindowRecoveryAndInvalidValueArePreserved() {
        var ledger = UsageEventLedger()
        _ = ledger.observe(observation(1_000))
        let missing = ledger.observe(observation(1_060, windows: []))
        XCTAssertTrue(missing.contains { $0.kind == .windowUnavailable && $0.windowID == "codex:primary" })

        let restored = ledger.observe(observation(1_120))
        XCTAssertTrue(restored.contains { $0.kind == .windowRestored && $0.windowID == "codex:primary" })

        let invalid = ledger.observe(observation(1_180, used: 140))
        XCTAssertTrue(invalid.contains { $0.kind == .windowUnavailable && $0.detailCode == "invalidWindowValue" })
        XCTAssertNil(ledger.state.latestObservation?.quotaWindows.first?.usedPercent)
    }

    func testFailureDeduplicationRecoveryAndStateRoundTrip() throws {
        var ledger = UsageEventLedger()
        let failed = ledger.recordFailure(sourceID: "codex.quota", timestamp: 1_000,
                                          accountKey: "account-A", errorCode: "timeout")
        XCTAssertEqual(failed.map(\.kind), [.sourceFailure])
        XCTAssertTrue(ledger.recordFailure(sourceID: "codex.quota", timestamp: 1_100,
                                           accountKey: "account-A", errorCode: "timeout").isEmpty)
        XCTAssertEqual(ledger.state.eventCount, 1)

        let recovered = ledger.observe(observation(1_200))
        XCTAssertTrue(recovered.contains { $0.kind == .sourceRecovered && $0.sourceID == "codex.quota" })
        XCTAssertEqual(ledger.state.eventCount, 3)
        let decodedState = try JSONDecoder().decode(UsageEventLedgerState.self,
                                                   from: JSONEncoder().encode(ledger.state))
        XCTAssertEqual(decodedState, ledger.state)
        let decodedEvent = try JSONDecoder().decode(UsageLedgerEvent.self,
                                                   from: JSONEncoder().encode(ledger.recentEvents[0]))
        XCTAssertEqual(decodedEvent, ledger.recentEvents[0])
    }

    func testTokenFailureIsRecordedWithoutDiscardingFreshQuotaObservation() {
        var ledger = UsageEventLedger()
        let events = ledger.observe(observation(1_000, tokens: nil, tokenHealth: .error,
                                               tokenError: "tokenTimeout"))
        XCTAssertTrue(events.contains { $0.kind == .checkpoint })
        XCTAssertTrue(events.contains { $0.kind == .sourceFailure && $0.sourceID == "codex.accountTokens" })
        XCTAssertEqual(ledger.state.latestObservation?.quotaHealth, .fresh)
        XCTAssertEqual(ledger.state.latestObservation?.tokenHealth, .error)
    }

    func testFailureFromPriorAccountIsNotReportedAsRecoveryOnNewAccount() {
        var ledger = UsageEventLedger()
        _ = ledger.observe(observation(900, account: "account-A"))
        _ = ledger.recordFailure(sourceID: "codex.accountTokens", timestamp: 1_000,
                                 accountKey: "account-A", errorCode: "tokenTimeout")
        let events = ledger.observe(observation(1_060, account: "account-B"))
        XCTAssertTrue(events.contains { $0.kind == .accountSwitch })
        XCTAssertFalse(events.contains { $0.kind == .sourceRecovered && $0.sourceID == "codex.accountTokens" })
        XCTAssertNil(ledger.state.activeFailures["codex.accountTokens"])
    }
}
