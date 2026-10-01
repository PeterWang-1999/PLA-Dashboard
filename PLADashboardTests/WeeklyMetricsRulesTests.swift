import XCTest
@testable import PLADashboard

final class WeeklyMetricsRulesTests: XCTestCase {
    func testRelativeDeltaUsesProductOverOverallMinusOne() {
        let delta = WeeklyMetricsRules.relativeDelta(product: 110, overall: 100)
        XCTAssertEqual(delta!, 0.1, accuracy: 0.0001)
    }

    func testARPUEqualsCVRTimesAOS() {
        let metrics = AggregatedMetrics(
            costCents: 10_000,
            clicks: 100,
            conversions: 10,
            conversionValueCents: 50_000
        )
        XCTAssertEqual(metrics.cvr, 0.1, accuracy: 0.0001)
        XCTAssertEqual(metrics.aos, 50, accuracy: 0.0001)
        XCTAssertEqual(metrics.arpu, 5, accuracy: 0.0001)
    }

    func testAOSUsesConversionValue() {
        let metrics = AggregatedMetrics(conversions: 2, conversionValueCents: 10_000)
        XCTAssertEqual(metrics.aos, 50, accuracy: 0.0001)
    }

}
