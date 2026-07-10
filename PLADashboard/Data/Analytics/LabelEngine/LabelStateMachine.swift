import Foundation

/// 入池 / 留池 / 出池状态机（对标 Python `state_machine._apply_state_machine`）。
enum LabelStateMachine {
    static func apply(
        metrics: LabelMetricsResult,
        previousProducts: [String: LabelSnapshotProductState],
        historyNote: String
    ) -> LabelStateMachineResult {
        let thresholds = metrics.thresholds
        var decisions: [LabelProductDecision] = []
        decisions.reserveCapacity(metrics.products.count)

        for row in metrics.products {
            let prev = previousProducts[row.productId] ?? .observationDefault
            decisions.append(decide(row: row, prev: prev, thresholds: thresholds))
        }

        return LabelStateMachineResult(decisions: decisions, historyNote: historyNote)
    }

    // MARK: - Per product

    private static func decide(
        row: LabelProductMetricsRow,
        prev: LabelSnapshotProductState,
        thresholds: LabelMetricsThresholds
    ) -> LabelProductDecision {
        let flags = RuleFlags(row: row, thresholds: thresholds)
        let prevLabel = normalizedLabel(prev.label)

        var label = LabelEngineConstants.labelObservation
        var action = "保持普通/观察"
        var reasonCore = "不满足任一入池条件"

        switch prevLabel {
        case LabelEngineConstants.labelObservation:
            if flags.enterHigh {
                label = LabelEngineConstants.labelHigh
                action = "新入高效"
                reasonCore = "满足高效入池"
            } else if flags.enterLow {
                label = LabelEngineConstants.labelLow
                action = "新入低效"
                reasonCore = "满足低效入池"
            } else if flags.enterPotential {
                label = LabelEngineConstants.labelPotential
                action = "新入潜力新品"
                reasonCore = "满足潜力新品入池"
            } else if flags.enterOld {
                label = LabelEngineConstants.labelOld
                action = "新入低样本老品"
                reasonCore = "满足低样本老品入池"
            }

        case LabelEngineConstants.labelHigh:
            let exitHigh = flags.noSignalRecent3
                || (flags.marginLt1 && prev.marginLt1)
                || (flags.failHighRetain && prev.failHighRetain)
            if exitHigh {
                if flags.enterLow {
                    label = LabelEngineConstants.labelLow
                    action = "高效出池→低效"
                    reasonCore = "满足低效入池"
                } else {
                    label = LabelEngineConstants.labelObservation
                    action = "高效出池→普通/观察"
                    reasonCore = "高效出池"
                }
                if flags.noSignalRecent3 {
                    reasonCore = "近3周无广告转化且无Gross Sales"
                } else if flags.marginLt1 && prev.marginLt1 {
                    reasonCore = "毛利回报连续2次<1.0"
                } else if flags.failHighRetain && prev.failHighRetain {
                    reasonCore = "连续2次不满足高效留池"
                }
            } else if flags.retainHigh {
                label = LabelEngineConstants.labelHigh
                action = "高效留池"
                reasonCore = "满足高效留池"
            } else {
                label = LabelEngineConstants.labelHigh
                action = "高效留池(首次未达标，暂留)"
                reasonCore = "本周不满足留池，但未连续2次，暂留高效"
            }

        case LabelEngineConstants.labelPotential:
            if row.clicks6w >= LabelEngineConstants.highClickMin {
                if flags.enterHigh {
                    label = LabelEngineConstants.labelHigh
                    action = "潜力新品晋升高效"
                    reasonCore = "点击>=300且满足高效入池"
                } else if flags.enterLow {
                    label = LabelEngineConstants.labelLow
                    action = "潜力新品转低效"
                    reasonCore = "点击>=300且满足低效入池"
                } else {
                    label = LabelEngineConstants.labelObservation
                    action = "潜力新品转普通/观察"
                    reasonCore = "点击>=300后不满足高效/低效"
                }
            } else if !row.isNewByFirstListed3m {
                if flags.enterHigh {
                    label = LabelEngineConstants.labelHigh
                    action = "潜力新品出池→高效"
                    reasonCore = "新品周期结束但满足高效入池"
                } else {
                    label = LabelEngineConstants.labelObservation
                    action = "潜力新品出池→普通/观察"
                    reasonCore = "新品周期结束但不满足高效"
                }
            } else if flags.noConvGSCurrentWeek && prev.noConvGSCurrentWeek {
                label = LabelEngineConstants.labelObservation
                action = "潜力新品出池→普通/观察"
                reasonCore = "连续2次周度更新无广告转化且无Gross Sales"
            } else if flags.retainPotential {
                label = LabelEngineConstants.labelPotential
                action = "潜力新品留池"
                reasonCore = "满足潜力新品留池/入池"
            } else if flags.enterPotential {
                label = LabelEngineConstants.labelPotential
                action = "潜力新品再入池"
                reasonCore = "满足潜力新品留池/入池"
            } else {
                label = LabelEngineConstants.labelPotential
                action = "潜力新品留池(未达标，暂留)"
                reasonCore = "本周不满足留池，但未触发出池条件，暂留潜力新品"
            }

        case LabelEngineConstants.labelOld:
            let candidateWeeksOld = prev.weeksInLowSampleOld + 1
            if row.clicks6w >= LabelEngineConstants.highClickMin {
                if flags.enterHigh {
                    label = LabelEngineConstants.labelHigh
                    action = "低样本老品晋升高效"
                    reasonCore = "点击>=300且满足高效入池"
                } else if flags.enterLow {
                    label = LabelEngineConstants.labelLow
                    action = "低样本老品转低效"
                    reasonCore = "点击>=300且满足低效入池"
                } else {
                    label = LabelEngineConstants.labelObservation
                    action = "低样本老品转普通/观察"
                    reasonCore = "点击>=300后不满足高效/低效"
                }
            } else {
                let exitOld = (flags.noConvGSCurrentWeek && prev.noConvGSCurrentWeek)
                    || (flags.marginLt1 && prev.marginLt1)
                    || (candidateWeeksOld >= LabelEngineConstants.oldTestWeeksLimit
                        && row.clicks6w < LabelEngineConstants.oldClickMin)
                if exitOld {
                    label = LabelEngineConstants.labelObservation
                    action = "低样本老品出池→普通/观察"
                    if flags.noConvGSCurrentWeek && prev.noConvGSCurrentWeek {
                        reasonCore = "连续2次周度更新无广告转化且无Gross Sales"
                    } else if flags.marginLt1 && prev.marginLt1 {
                        reasonCore = "毛利回报连续2次<1.0"
                    } else {
                        reasonCore = "进入测试系列6周后近6周点击仍<50"
                    }
                } else if flags.retainOld {
                    label = LabelEngineConstants.labelOld
                    action = "低样本老品留池"
                    reasonCore = "满足低样本老品留池/入池"
                } else if flags.enterOld {
                    label = LabelEngineConstants.labelOld
                    action = "低样本老品再入池"
                    reasonCore = "满足低样本老品留池/入池"
                } else {
                    label = LabelEngineConstants.labelOld
                    action = "低样本老品留池(未达标，暂留)"
                    reasonCore = "本周不满足留池，但未触发出池条件，暂留低样本老品"
                }
            }

        case LabelEngineConstants.labelLow:
            let exitLow = (flags.roiGe1x && prev.roiGe1x) || (flags.marginGe1 && prev.marginGe1)
            if exitLow {
                if flags.enterHigh {
                    label = LabelEngineConstants.labelHigh
                    action = "低效出池→高效"
                    reasonCore = "连续2次恢复且满足高效入池"
                } else {
                    label = LabelEngineConstants.labelObservation
                    action = "低效出池→普通/观察"
                    if flags.roiGe1x && prev.roiGe1x {
                        reasonCore = "连续2次广告ROI>=1.0x基准"
                    } else {
                        reasonCore = "连续2次毛利回报>=1.0"
                    }
                }
            } else if flags.retainLow {
                label = LabelEngineConstants.labelLow
                action = "低效留池"
                reasonCore = "满足低效留池/入池"
            } else if flags.enterLow {
                label = LabelEngineConstants.labelLow
                action = "低效再入池"
                reasonCore = "满足低效留池/入池"
            } else {
                label = LabelEngineConstants.labelLow
                action = "低效留池(首次恢复信号，暂留)"
                reasonCore = "出现恢复信号但未连续2次，暂留低效"
            }

        default:
            // 未知上周标签：按普通/观察入池
            if flags.enterHigh {
                label = LabelEngineConstants.labelHigh
                action = "新入高效"
                reasonCore = "满足高效入池"
            } else if flags.enterLow {
                label = LabelEngineConstants.labelLow
                action = "新入低效"
                reasonCore = "满足低效入池"
            } else if flags.enterPotential {
                label = LabelEngineConstants.labelPotential
                action = "新入潜力新品"
                reasonCore = "满足潜力新品入池"
            } else if flags.enterOld {
                label = LabelEngineConstants.labelOld
                action = "新入低样本老品"
                reasonCore = "满足低样本老品入池"
            }
        }

        let weeksPot: Int
        if label == LabelEngineConstants.labelPotential {
            weeksPot = (prevLabel == LabelEngineConstants.labelPotential)
                ? prev.weeksInPotentialNew + 1
                : 1
        } else {
            weeksPot = 0
        }

        let weeksOld: Int
        if label == LabelEngineConstants.labelOld {
            weeksOld = (prevLabel == LabelEngineConstants.labelOld)
                ? prev.weeksInLowSampleOld + 1
                : 1
        } else {
            weeksOld = 0
        }

        let benchText: String
        if let bench = row.appliedBenchmarkROI, bench.isFinite {
            benchText = String(format: "%.2f", bench)
        } else {
            benchText = "NA"
        }
        let reason = "主类目=\(row.primaryCMS3)；按\(row.benchmarkSource) \(benchText)比较；上周标签=\(prevLabel)；动作=\(action)；\(reasonCore)"

        return LabelProductDecision(
            productId: row.productId,
            previousLabel: prevLabel,
            suggestedLabel: label,
            transitionAction: action,
            reason: reason,
            failHighRetain: flags.failHighRetain,
            marginLt1: flags.marginLt1,
            noSignalRecent3: flags.noSignalRecent3,
            noConvGSCurrentWeek: flags.noConvGSCurrentWeek,
            roiGe1x: flags.roiGe1x,
            marginGe1: flags.marginGe1,
            weeksInLowSampleOld: weeksOld,
            weeksInPotentialNew: weeksPot
        )
    }

    // MARK: - Flags

    private struct RuleFlags {
        let enterHigh: Bool
        let enterLow: Bool
        let enterPotential: Bool
        let enterOld: Bool
        let retainHigh: Bool
        let retainPotential: Bool
        let retainOld: Bool
        let retainLow: Bool
        let noSignalRecent3: Bool
        let noConvGSCurrentWeek: Bool
        let marginLt1: Bool
        let failHighRetain: Bool
        let roiGe1x: Bool
        let marginGe1: Bool

        init(row: LabelProductMetricsRow, thresholds: LabelMetricsThresholds) {
            let normal = row.dataNormal
            let benchOK = row.appliedBenchmarkROI.map { $0.isFinite } ?? false
            let bench = row.appliedBenchmarkROI ?? .nan
            let roi = row.weightedAdROI ?? .nan
            let margin = row.weightedMarginReturn ?? .nan
            let wgs = row.weightedGrossSalesCents
            let clicks = row.clicks6w
            let active3 = row.activeWeeksRecent3
            let conv = row.conversions6w
            let isNew = row.isNewByFirstListed3m

            enterHigh = normal && benchOK
                && clicks >= LabelEngineConstants.highClickMin
                && roi >= LabelEngineConstants.highROIMultiplier * bench
                && margin >= thresholds.highMarginThreshold
                && active3 >= 2
                && conv >= LabelEngineConstants.highConversionsMin

            enterLow = normal && benchOK
                && clicks >= LabelEngineConstants.highClickMin
                && (roi <= LabelEngineConstants.lowROIMultiplier * bench || conv == 0)
                && margin < 1.0

            let gsP75 = Self.meetsGS(wgs, thresholds.newGSP75Cents)
            enterPotential = normal && benchOK
                && isNew
                && clicks < LabelEngineConstants.highClickMin
                && (conv > 0 || wgs > 0)
                && active3 >= 1
                && (roi >= LabelEngineConstants.newROIMultiplier * bench || gsP75)
                && margin >= 1.0

            let oldGSP50 = Self.meetsGS(wgs, thresholds.oldGSP50Cents)
            enterOld = normal && benchOK
                && !isNew
                && clicks >= LabelEngineConstants.oldClickMin
                && clicks < LabelEngineConstants.highClickMin
                && (conv > 0 || wgs > 0)
                && active3 >= 1
                && (roi >= LabelEngineConstants.oldROIMultiplier * bench || oldGSP50)
                && margin >= 1.0

            retainHigh = normal && benchOK
                && roi >= 1.0 * bench
                && margin >= 1.0
                && active3 >= 1

            let gsP50 = Self.meetsGS(wgs, thresholds.newGSP50Cents)
            retainPotential = normal && benchOK
                && isNew
                && clicks < LabelEngineConstants.highClickMin
                && active3 >= 1
                && (roi >= 1.0 * bench || gsP50)
                && margin >= 1.0

            retainOld = normal && benchOK
                && !isNew
                && clicks >= LabelEngineConstants.oldClickMin
                && clicks < LabelEngineConstants.highClickMin
                && active3 >= 1
                && (roi >= 1.0 * bench || oldGSP50)
                && margin >= 1.0

            let significantRecovery = active3 >= 2 || roi >= 1.0 * bench || margin >= 1.0
            retainLow = normal && benchOK
                && roi < LabelEngineConstants.lowRetainROIMultiplier * bench
                && margin < 1.0
                && !significantRecovery

            noSignalRecent3 = active3 <= 0
            noConvGSCurrentWeek = row.noConvGSCurrentWeek
            marginLt1 = margin < 1.0
            failHighRetain = !retainHigh
            roiGe1x = benchOK && roi >= 1.0 * bench
            marginGe1 = margin >= 1.0
        }

        private static func meetsGS(_ wgs: Double, _ threshold: Double?) -> Bool {
            guard let threshold, threshold.isFinite else { return false }
            return wgs >= threshold
        }
    }

    private static func normalizedLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        switch trimmed {
        case LabelEngineConstants.labelHigh,
             LabelEngineConstants.labelPotential,
             LabelEngineConstants.labelOld,
             LabelEngineConstants.labelLow,
             LabelEngineConstants.labelObservation:
            return trimmed
        default:
            return LabelEngineConstants.labelObservation
        }
    }
}
