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

    func testWeightedROIUsesSixWeekWeights() {
        let weekly = [
            AggregatedMetrics(costCents: 100, conversionValueCents: 100),
            AggregatedMetrics(costCents: 100, conversionValueCents: 200),
            AggregatedMetrics(costCents: 100, conversionValueCents: 300),
            AggregatedMetrics(costCents: 100, conversionValueCents: 400),
            AggregatedMetrics(costCents: 100, conversionValueCents: 500),
            AggregatedMetrics(costCents: 100, conversionValueCents: 600),
        ]
        let weighted = WeeklyMetricsRules.weightedROI(weeklyMetrics: weekly)
        let expected = (1.0 * 0.14) + (2.0 * 0.15) + (3.0 * 0.16) + (4.0 * 0.17) + (5.0 * 0.18) + (6.0 * 0.20)
        XCTAssertEqual(weighted, expected, accuracy: 0.0001)
    }

    func testResolveLowSpendLabel() {
        let weekStarts = (0..<6).map { "2026-06-\(String(format: "%02d", $0 + 1))" }
        let productMetrics = weekStarts.map {
            WeeklyProductMetrics(
                productId: "p1",
                weekStart: $0,
                metrics: AggregatedMetrics(costCents: 100, clicks: 400, conversionValueCents: 500)
            )
        }
        let overallMetrics = weekStarts.map {
            WeeklyProductMetrics(
                productId: "__overall__",
                weekStart: $0,
                metrics: AggregatedMetrics(costCents: 1_000, clicks: 10_000, conversionValueCents: 250)
            )
        }
        let label = WeeklyMetricsRules.resolveWarningLabel(
            productWeeks: productMetrics,
            overallWeeks: overallMetrics
        )
        XCTAssertEqual(label, .lowSpend)
    }

    func testHighEfficiencyUsesMultiplier16() {
        XCTAssertEqual(AnalyticsConfiguration.highEfficiencyROIMultiplier, 1.6)
    }
}
