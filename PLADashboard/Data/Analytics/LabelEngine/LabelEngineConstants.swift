import Foundation

/// 自建站预警标签引擎常量（对标 Python `label_engine/constants.py`）。
enum LabelEngineConstants: Sendable {
    /// 由旧到新，共 6 周。
    static let weekWeights: [Double] = [0.14, 0.15, 0.16, 0.17, 0.18, 0.20]

    static let reportingWeekCount = 6
    static let recentActiveLookbackWeeks = 3

    /// 类目样本充足：近 6 周花费（美元）。
    static let categoryCostMinDollars: Double = 4_000
    static let categoryClicksMin = 6_000
    static let categoryConversionsMin: Double = 40
    static let categorySpendProductsMin = 50

    static let highClickMin = 300
    static let highROIMultiplier = 1.2
    static let highConversionsMin: Double = 3
    static let lowROIMultiplier = 0.8
    static let lowRetainROIMultiplier = 0.9
    static let newROIMultiplier = 1.5
    static let oldClickMin = 50
    static let oldROIMultiplier = 1.2
    static let oldTestWeeksLimit = 6

    static let labelHigh = "高效"
    static let labelPotential = "潜力新品"
    static let labelOld = "低样本老品"
    static let labelLow = "低效"
    static let labelObservation = "普通/观察"

    static let benchmarkSourceCategory = "CMS3类目基准"
    static let benchmarkSourceSite = "全站大盘基准"
    static let unclassifiedCMS3 = "未分类"
}
