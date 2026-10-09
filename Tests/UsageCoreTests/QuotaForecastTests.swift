import XCTest
@testable import UsageCore

final class QuotaForecastTests: XCTestCase {
    func testOnTrackTightAndExhausting() {
        let now = 1_000_000.0
        let onTrack = forecastQuota(used: 20, perHour: 5, resetsAt: now + 4 * 3600, now: now)
        XCTAssertEqual(onTrack?.projectedUsedAtReset, 40)
        XCTAssertNil(onTrack?.exhaustsAt)
        XCTAssertEqual(onTrack?.outlook, .onTrack)

        let tight = forecastQuota(used: 80, perHour: 5, resetsAt: now + 2 * 3600, now: now)
        XCTAssertEqual(tight?.projectedUsedAtReset, 90)
        XCTAssertEqual(tight?.outlook, .tight)

        let exhausts = forecastQuota(used: 60, perHour: 10, resetsAt: now + 10 * 3600, now: now)
        XCTAssertEqual(exhausts?.projectedUsedAtReset, 100)
        XCTAssertEqual(exhausts?.exhaustsAt, now + 4 * 3600)
        XCTAssertEqual(exhausts?.outlook, .exhausts)
    }

    func testReachingExactlyAtResetCountsAsExhausting() {
        let now = 0.0
        let forecast = forecastQuota(used: 50, perHour: 25, resetsAt: 2 * 3600, now: now)
        XCTAssertEqual(forecast?.exhaustsAt, 2 * 3600)
    }

    func testZeroRateAndFullWindow() {
        let now = 500.0
        let idle = forecastQuota(used: 95, perHour: 0, resetsAt: now + 3600, now: now)
        XCTAssertEqual(idle?.projectedUsedAtReset, 95)
        XCTAssertNil(idle?.exhaustsAt)
        XCTAssertEqual(idle?.outlook, .tight)

        let full = forecastQuota(used: 100, perHour: 0, resetsAt: now + 3600, now: now)
        XCTAssertEqual(full?.exhaustsAt, now)
        XCTAssertEqual(full?.outlook, .exhausts)
    }

    func testInvalidInputsHaveNoForecast() {
        let now = 100.0
        XCTAssertNil(forecastQuota(used: nil, perHour: 1, resetsAt: now + 60, now: now))
        XCTAssertNil(forecastQuota(used: 101, perHour: 1, resetsAt: now + 60, now: now))
        XCTAssertNil(forecastQuota(used: 10, perHour: nil, resetsAt: now + 60, now: now))
        XCTAssertNil(forecastQuota(used: 10, perHour: -1, resetsAt: now + 60, now: now))
        XCTAssertNil(forecastQuota(used: 10, perHour: .nan, resetsAt: now + 60, now: now))
        XCTAssertNil(forecastQuota(used: 10, perHour: 1, resetsAt: nil, now: now))
        XCTAssertNil(forecastQuota(used: 10, perHour: 1, resetsAt: now, now: now))
    }

    func testForecastLabelsExistInEnglishAndChinese() {
        for key in forecastTranslations.keys {
            for code in ["en", "zh-Hant", "zh-Hans"] {
                XCTAssertNotNil(L10n.table[key]?[code], "\(key) missing \(code)")
            }
        }
    }
}
