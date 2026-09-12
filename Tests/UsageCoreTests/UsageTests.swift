import XCTest
@testable import UsageCore

final class UsageTests: XCTestCase {
    let base: Double = 1_000_000
    func items(_ used: Double, reset: Double? = 2_000_000, duration: Int = 10080) -> [WindowItem] {
        [WindowItem(id: "codex:primary", name: "Codex", window: QuotaWindow(usedPercent: used, windowDurationMins: duration, resetsAt: reset))]
    }
    func record(_ h: inout History, seconds: Int, used: Double, account: String = "A", reset: Double? = 2_000_000) {
        h.record(account: account, items: items(used, reset: reset), now: base+Double(seconds))
    }
    func testHourlyIncreaseAndRollingBoundary() {
        var h = History()
        for minute in 0...70 { record(&h, seconds: minute*60, used: 20+Double(minute)*5/60) }
        let rate = h.rate(for: "codex:primary", now: base+4200)!
        XCTAssertEqual(rate.perHour, 5, accuracy: 0.0001)
        XCTAssertEqual(rate.observedSeconds, 3600)
    }
    func testInterpolationAtIrregularBoundary() {
        var h = History()
        for second in stride(from: 0, through: 3660, by: 61) { record(&h, seconds: second, used: 20+Double(second)*5/3600) }
        XCTAssertEqual(h.rate(for: "codex:primary", now: base+3660)!.perHour, 5, accuracy: 0.0001)
    }
    func testWarmupAndIdle() {
        var h = History()
        for minute in 0...4 { record(&h, seconds: minute*60, used: 20) }
        XCTAssertNil(h.rate(for: "codex:primary", now: base+240))
        record(&h, seconds: 300, used: 20)
        XCTAssertEqual(h.rate(for: "codex:primary", now: base+300)!.perHour, 0)
    }
    func testResetsDropsAccountsAndGapsBreakHistory() {
        for scenario in 0...3 {
            var h = History()
            for minute in 0...5 { record(&h, seconds: minute*60, used: 20+Double(minute)) }
            switch scenario {
            case 0: record(&h, seconds: 360, used: 26, reset: 3_000_000)
            case 1: record(&h, seconds: 360, used: 5)
            case 2: record(&h, seconds: 360, used: 26, account: "B")
            default: record(&h, seconds: 601, used: 26)
            }
            XCTAssertEqual(h.series["codex:primary"]?.count, 1)
            XCTAssertNil(h.rate(for: "codex:primary", now: base+601))
        }
    }
    func testStaleAndExpiredWindowHaveNoRate() {
        var h = History()
        for minute in 0...5 { record(&h, seconds: minute*60, used: 20+Double(minute), reset: base+700) }
        XCTAssertNil(h.rate(for: "codex:primary", now: base+601))
        XCTAssertNil(h.rate(for: "codex:primary", now: base+701))
    }
    func testRetentionAndSerialization() throws {
        var h = History()
        for minute in 0...1500 { record(&h, seconds: minute*60, used: 20) }
        XCTAssertEqual(h.series["codex:primary"]?.count, 1501)
        let decoded = try JSONDecoder().decode(History.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(decoded.account, "A")
        XCTAssertEqual(decoded.series["codex:primary"]?.count, 1501)
    }
    func testDecodeWeeklyMultiBucketMissingAndLegacy() throws {
        let json = #"{"rateLimitsByLimitId":{"spark":{"limitName":"Spark","primary":{"usedPercent":0,"windowDurationMins":300},"secondary":{"usedPercent":9,"windowDurationMins":10080}},"codex":{"primary":{"usedPercent":25,"windowDurationMins":10080,"resetsAt":2000000},"secondary":null}}}"#
        let result = try JSONDecoder().decode(LimitsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(result.windows().map(\.id), ["codex:primary", "spark:primary", "spark:secondary"])
        XCTAssertEqual(result.windows()[0].title, "Codex · 1週")
        XCTAssertNil(result.windows()[1].window.resetsAt)
        let legacy = #"{"rateLimits":{"primary":{"usedPercent":12}}}"#
        XCTAssertEqual(try JSONDecoder().decode(LimitsResponse.self, from: Data(legacy.utf8)).windows().count, 1)
        XCTAssertTrue(try JSONDecoder().decode(LimitsResponse.self, from: Data("{}".utf8)).windows().isEmpty)
        XCTAssertThrowsError(try JSONDecoder().decode(LimitsResponse.self, from: Data(#"{"rateLimits":42}"#.utf8)))
    }
    func testCountdownDoesNotInferResetAndNullIsUnknown() {
        XCTAssertEqual(countdown(base, now: base+1), "等待重置確認")
        XCTAssertEqual(countdown(nil, now: base), "重置時間未知")
        XCTAssertEqual(countdown(base+3661, now: base), "01:01:01")
        XCTAssertEqual(durationLabel(nil), "週期未知")
    }
    func testWindowsRemainIndependentAndMissingInvalidWindowsReset() {
        var h = History()
        for minute in 0...5 {
            let a = items(20+Double(minute))[0]
            let b = WindowItem(id: "spark:primary", name: "Spark", window: QuotaWindow(usedPercent: 0, windowDurationMins: 300, resetsAt: 2_000_000))
            h.record(account: "A", items: [a,b], now: base+Double(minute*60))
        }
        XCTAssertEqual(h.rate(for: "spark:primary", now: base+300)!.perHour, 0)
        XCTAssertEqual(h.rate(for: "codex:primary", now: base+300)!.perHour, 60)
        h.record(account: "A", items: items(101), now: base+360)
        XCTAssertTrue(h.series.isEmpty)
    }
    func testMonitorRemovalResolutionAndNegativeCoordinates() {
        let main = CGRect(x: 0, y: 0, width: 1920, height: 1055)
        let left = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let card = CGRect(x: -1000, y: 700, width: 220, height: 100)
        XCTAssertEqual(visibleOrigin(for: card, screens: [main, left]), card.origin)
        XCTAssertEqual(visibleOrigin(for: card, screens: [main]), CGPoint(x: 0, y: 700))
        XCTAssertEqual(visibleOrigin(for: CGRect(x: 1850, y: 1000, width: 220, height: 100), screens: [main]), CGPoint(x: 1700, y: 955))
    }

}
