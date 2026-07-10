import Foundation

enum LabelMetricsBuilderError: Error, LocalizedError, Sendable {
    case invalidWeekCount(Int)
    case weightCountMismatch
    case invalidCurrentWeekStart(String)

    var errorDescription: String? {
        switch self {
        case .invalidWeekCount(let count):
            "标签指标需要恰好 \(LabelEngineConstants.reportingWeekCount) 个完整周，当前为 \(count)"
        case .weightCountMismatch:
            "周权重数量与报告周数不一致"
        case .invalidCurrentWeekStart(let value):
            "无法解析当前周起始日：\(value)"
        }
    }
}

/// 纯计算：由周事实 + 产品维表构建标签指标与动态阈值（对标 `metrics._build_metrics`）。
enum LabelMetricsBuilder {
    static func build(
        weekStarts: [String],
        weeklyFacts: [LabelWeeklyFact],
        products: [LabelProductMeta],
        weights: [Double] = LabelEngineConstants.weekWeights
    ) throws -> LabelMetricsResult {
        guard weekStarts.count == LabelEngineConstants.reportingWeekCount else {
            throw LabelMetricsBuilderError.invalidWeekCount(weekStarts.count)
        }
        guard weights.count == weekStarts.count else {
            throw LabelMetricsBuilderError.weightCountMismatch
        }

        let weightByWeek = Dictionary(uniqueKeysWithValues: zip(weekStarts, weights))
        let recent3 = Array(weekStarts.suffix(LabelEngineConstants.recentActiveLookbackWeeks))
        let currentWeek = weekStarts[weekStarts.count - 1]
        let weekStartSet = Set(weekStarts)

        let metaByID = Dictionary(
            products.map { ($0.productId, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        // productId → weekStart → fact（同键后者覆盖，调用方应已去重）
        var factsByProduct: [String: [String: LabelWeeklyFact]] = [:]
        factsByProduct.reserveCapacity(min(weeklyFacts.count, 4_096))
        for fact in weeklyFacts where weekStartSet.contains(fact.weekStart) {
            factsByProduct[fact.productId, default: [:]][fact.weekStart] = fact
        }

        let productIDs = factsByProduct.keys.sorted()
        let newCutoffDay = try newProductCutoffDay(currentWeekStart: currentWeek)

        // —— 类目基准（按产品主 CMS3 聚合广告周数据）——
        struct CategoryAccum {
            var costCents = 0
            var clicks = 0
            var conversions = 0.0
            var conversionValueCents = 0
            var weightedCost = 0.0
            var weightedCV = 0.0
            var productCostCents: [String: Int] = [:]
        }

        var categoryAccums: [String: CategoryAccum] = [:]
        for productId in productIDs {
            let cms3 = normalizedCMS3(metaByID[productId]?.cms3)
            var accum = categoryAccums[cms3] ?? CategoryAccum()
            var productCost = 0
            for week in weekStarts {
                guard let fact = factsByProduct[productId]?[week] else { continue }
                let w = weightByWeek[week] ?? 0
                accum.costCents += fact.costCents
                accum.clicks += fact.clicks
                accum.conversions += fact.conversions
                accum.conversionValueCents += fact.conversionValueCents
                accum.weightedCost += Double(fact.costCents) * w
                accum.weightedCV += Double(fact.conversionValueCents) * w
                productCost += fact.costCents
            }
            accum.productCostCents[productId] = productCost
            categoryAccums[cms3] = accum
        }

        let categories: [LabelCategoryBenchmark] = categoryAccums.keys.sorted().map { cms3 in
            let a = categoryAccums[cms3]!
            let spendProducts = a.productCostCents.values.filter { $0 > 0 }.count
            let costDollars = Double(a.costCents) / 100.0
            var reasons: [String] = []
            if costDollars < LabelEngineConstants.categoryCostMinDollars {
                reasons.append("类目花费<\(Int(LabelEngineConstants.categoryCostMinDollars))")
            }
            if a.clicks < LabelEngineConstants.categoryClicksMin {
                reasons.append("类目点击<\(LabelEngineConstants.categoryClicksMin)")
            }
            if a.conversions < LabelEngineConstants.categoryConversionsMin {
                reasons.append("类目广告转化<\(Int(LabelEngineConstants.categoryConversionsMin))")
            }
            if spendProducts < LabelEngineConstants.categorySpendProductsMin {
                reasons.append("有花费产品数<\(LabelEngineConstants.categorySpendProductsMin)")
            }
            let sufficient = reasons.isEmpty
            let roi = safeDiv(a.weightedCV, a.weightedCost)
            return LabelCategoryBenchmark(
                cms3: cms3,
                cost6wCents: a.costCents,
                clicks6w: a.clicks,
                conversions6w: a.conversions,
                conversionValue6wCents: a.conversionValueCents,
                spendProducts6w: spendProducts,
                products6w: a.productCostCents.count,
                weightedCostCents: a.weightedCost,
                weightedConversionValueCents: a.weightedCV,
                benchmarkROI: roi,
                sampleSufficient: sufficient,
                insufficientReason: reasons.joined(separator: "；")
            )
        }
        let categoryByCMS3 = Dictionary(uniqueKeysWithValues: categories.map { ($0.cms3, $0) })

        var siteWeightedCost = 0.0
        var siteWeightedCV = 0.0
        for a in categoryAccums.values {
            siteWeightedCost += a.weightedCost
            siteWeightedCV += a.weightedCV
        }
        let siteBenchmarkROI = safeDiv(siteWeightedCV, siteWeightedCost)

        // —— 产品行 ——
        var rows: [LabelProductMetricsRow] = []
        rows.reserveCapacity(productIDs.count)

        for productId in productIDs {
            let meta = metaByID[productId]
            let cms3 = normalizedCMS3(meta?.cms3)
            let weeks = factsByProduct[productId] ?? [:]

            var cost = 0
            var impressions = 0
            var clicks = 0
            var conversions = 0.0
            var cv = 0
            var gs = 0
            var gp = 0
            var weeksWithData = 0
            var wCost = 0.0
            var wCV = 0.0
            var wGS = 0.0
            var wGP = 0.0
            var activeRecent3 = 0
            var activeCurrent = false

            for week in weekStarts {
                let fact = weeks[week] ?? LabelWeeklyFact(
                    productId: productId,
                    weekStart: week,
                    costCents: 0,
                    impressions: 0,
                    clicks: 0,
                    conversions: 0,
                    conversionValueCents: 0,
                    grossSalesCents: 0,
                    grossProfitCents: 0
                )
                let w = weightByWeek[week] ?? 0
                cost += fact.costCents
                impressions += fact.impressions
                clicks += fact.clicks
                conversions += fact.conversions
                cv += fact.conversionValueCents
                gs += fact.grossSalesCents
                gp += fact.grossProfitCents
                if fact.costCents > 0 { weeksWithData += 1 }
                wCost += Double(fact.costCents) * w
                wCV += Double(fact.conversionValueCents) * w
                wGS += Double(fact.grossSalesCents) * w
                wGP += Double(fact.grossProfitCents) * w

                let active = fact.conversions > 0 || fact.grossSalesCents > 0
                if recent3.contains(week), active {
                    activeRecent3 += 1
                }
                if week == currentWeek {
                    activeCurrent = active
                }
            }

            let adROI = safeDiv(wCV, wCost)
            let marginReturn = safeDiv(wGP, wCost)
            let marginRate = safeDiv(Double(gp), Double(gs))
            let marginRateNormal = marginRate == nil
                || ((marginRate ?? 0) > 0 && (marginRate ?? 0) <= 1)
            let dataNormal = wCost > 0
                && adROI != nil
                && marginReturn != nil
                && wCV >= 0
                && wGS >= 0
                && wGP >= 0
                && marginRateNormal

            let isNew: Bool
            if let listed = meta?.firstListedAt, !listed.isEmpty {
                isNew = listed >= newCutoffDay
            } else {
                isNew = false
            }

            let cat = categoryByCMS3[cms3]
            let sufficient = cat?.sampleSufficient ?? false
            let applied: Double?
            let source: String
            if sufficient {
                applied = cat?.benchmarkROI
                source = LabelEngineConstants.benchmarkSourceCategory
            } else {
                applied = siteBenchmarkROI
                source = LabelEngineConstants.benchmarkSourceSite
            }

            rows.append(LabelProductMetricsRow(
                productId: productId,
                primaryCMS3: cms3,
                firstListedAt: meta?.firstListedAt,
                cost6wCents: cost,
                impressions6w: impressions,
                clicks6w: clicks,
                conversions6w: conversions,
                conversionValue6wCents: cv,
                grossSales6wCents: gs,
                grossProfit6wCents: gp,
                weeksWithData: weeksWithData,
                weightedCostCents: wCost,
                weightedConversionValueCents: wCV,
                weightedGrossSalesCents: wGS,
                weightedGrossProfitCents: wGP,
                weightedAdROI: adROI,
                weightedMarginReturn: marginReturn,
                realizedMarginRate: marginRate,
                activeWeeksRecent3: activeRecent3,
                activeCurrentWeek: activeCurrent,
                noConvGSCurrentWeek: !activeCurrent,
                isNewByFirstListed3m: isNew,
                dataNormal: dataNormal,
                categorySampleSufficient: sufficient,
                categoryBenchmarkROI: cat?.benchmarkROI,
                categoryInsufficientReason: sufficient
                    ? ""
                    : (cat?.insufficientReason.isEmpty == false
                        ? cat!.insufficientReason
                        : "无类目基准"),
                benchmarkSource: source,
                appliedBenchmarkROI: applied
            ))
        }

        let thresholds = makeThresholds(
            rows: rows,
            newCutoffDay: newCutoffDay,
            siteBenchmarkROI: siteBenchmarkROI
        )

        return LabelMetricsResult(
            weekStarts: weekStarts,
            currentWeekStart: currentWeek,
            products: rows,
            categories: categories,
            thresholds: thresholds
        )
    }

    // MARK: - Helpers

    static func safeDiv(_ numer: Double, _ denom: Double) -> Double? {
        guard denom.isFinite, denom != 0, numer.isFinite else { return nil }
        let value = numer / denom
        return value.isFinite ? value : nil
    }

    /// 线性插值分位（对标 pandas `quantile` 默认 `interpolation='linear'`）。
    static func percentile(_ values: [Double], _ probability: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if sorted.count == 1 { return sorted[0] }
        let clamped = min(max(probability, 0), 1)
        let index = clamped * Double(sorted.count - 1)
        let lower = Int(index.rounded(.down))
        let upper = Int(index.rounded(.up))
        if lower == upper { return sorted[lower] }
        let weight = index - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    static func normalizedCMS3(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty || trimmed == "-" || trimmed.lowercased() == "nan" {
            return LabelEngineConstants.unclassifiedCMS3
        }
        return trimmed
    }

    /// 当前完整周结束日（周六）往前 3 个日历月，作为新品 cutoff（`yyyy-MM-dd`）。
    static func newProductCutoffDay(currentWeekStart: String) throws -> String {
        guard let start = WeekCalendar.parseDay(currentWeekStart) else {
            throw LabelMetricsBuilderError.invalidCurrentWeekStart(currentWeekStart)
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: start),
              let cutoff = calendar.date(byAdding: .month, value: -3, to: weekEnd) else {
            throw LabelMetricsBuilderError.invalidCurrentWeekStart(currentWeekStart)
        }
        return WeekCalendar.formatDay(cutoff)
    }

    private static func makeThresholds(
        rows: [LabelProductMetricsRow],
        newCutoffDay: String,
        siteBenchmarkROI: Double?
    ) -> LabelMetricsThresholds {
        let matureMargins = rows.compactMap { row -> Double? in
            guard row.dataNormal,
                  row.clicks6w >= LabelEngineConstants.highClickMin,
                  !row.isNewByFirstListed3m,
                  let margin = row.weightedMarginReturn else {
                return nil
            }
            return margin
        }
        let matureP50 = percentile(matureMargins, 0.50)
        let highMarginThreshold = max(1.0, matureP50 ?? 1.0)

        let newGS = rows.compactMap { row -> Double? in
            guard row.isNewByFirstListed3m, row.weightedGrossSalesCents > 0 else { return nil }
            return row.weightedGrossSalesCents
        }
        let oldGS = rows.compactMap { row -> Double? in
            guard !row.isNewByFirstListed3m,
                  row.clicks6w >= LabelEngineConstants.oldClickMin,
                  row.clicks6w < LabelEngineConstants.highClickMin,
                  row.weightedGrossSalesCents > 0 else {
                return nil
            }
            return row.weightedGrossSalesCents
        }

        return LabelMetricsThresholds(
            highMarginThreshold: highMarginThreshold,
            matureMarginP50: matureP50,
            matureSampleN: matureMargins.count,
            newGSP50Cents: percentile(newGS, 0.50),
            newGSP75Cents: percentile(newGS, 0.75),
            newPositiveN: newGS.count,
            oldGSP50Cents: percentile(oldGS, 0.50),
            oldPositiveN: oldGS.count,
            newCutoffDay: newCutoffDay,
            siteBenchmarkROI: siteBenchmarkROI
        )
    }
}
