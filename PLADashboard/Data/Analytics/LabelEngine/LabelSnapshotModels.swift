import Foundation
import GRDB

struct LabelSnapshotRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "label_snapshots"

    var weekId: String
    var createdAt: String
    var adsWeeksJSON: String
    var historyNote: String?

    enum Columns: String, ColumnExpression {
        case weekId = "week_id"
        case createdAt = "created_at"
        case adsWeeksJSON = "ads_weeks_json"
        case historyNote = "history_note"
    }

    enum CodingKeys: String, CodingKey {
        case weekId = "week_id"
        case createdAt = "created_at"
        case adsWeeksJSON = "ads_weeks_json"
        case historyNote = "history_note"
    }
}

struct LabelSnapshotProductRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    static let databaseTableName = "label_snapshot_products"

    var weekId: String
    var productId: String
    var label: String
    var failHighRetain: Bool
    var marginLt1: Bool
    var noSignalRecent3: Bool
    var noConvGSCurrentWeek: Bool
    var roiGe1x: Bool
    var marginGe1: Bool
    var weeksInLowSampleOld: Int
    var weeksInPotentialNew: Int
    var transitionAction: String?
    var reason: String?

    enum Columns: String, ColumnExpression {
        case weekId = "week_id"
        case productId = "product_id"
        case label
        case failHighRetain = "fail_high_retain"
        case marginLt1 = "margin_lt_1"
        case noSignalRecent3 = "no_signal_recent3"
        case noConvGSCurrentWeek = "no_conv_gs_current_week"
        case roiGe1x = "roi_ge_1x"
        case marginGe1 = "margin_ge_1"
        case weeksInLowSampleOld = "weeks_in_low_sample_old"
        case weeksInPotentialNew = "weeks_in_potential_new"
        case transitionAction = "transition_action"
        case reason
    }

    enum CodingKeys: String, CodingKey {
        case weekId = "week_id"
        case productId = "product_id"
        case label
        case failHighRetain = "fail_high_retain"
        case marginLt1 = "margin_lt_1"
        case noSignalRecent3 = "no_signal_recent3"
        case noConvGSCurrentWeek = "no_conv_gs_current_week"
        case roiGe1x = "roi_ge_1x"
        case marginGe1 = "margin_ge_1"
        case weeksInLowSampleOld = "weeks_in_low_sample_old"
        case weeksInPotentialNew = "weeks_in_potential_new"
        case transitionAction = "transition_action"
        case reason
    }

    var asPreviousState: LabelSnapshotProductState {
        LabelSnapshotProductState(
            label: label,
            failHighRetain: failHighRetain,
            marginLt1: marginLt1,
            noConvGSCurrentWeek: noConvGSCurrentWeek,
            roiGe1x: roiGe1x,
            marginGe1: marginGe1,
            weeksInLowSampleOld: weeksInLowSampleOld,
            weeksInPotentialNew: weeksInPotentialNew
        )
    }
}

/// 上周快照中供状态机使用的产品状态。
struct LabelSnapshotProductState: Sendable, Hashable {
    var label: String
    var failHighRetain: Bool
    var marginLt1: Bool
    var noConvGSCurrentWeek: Bool
    var roiGe1x: Bool
    var marginGe1: Bool
    var weeksInLowSampleOld: Int
    var weeksInPotentialNew: Int

    static let observationDefault = LabelSnapshotProductState(
        label: LabelEngineConstants.labelObservation,
        failHighRetain: false,
        marginLt1: false,
        noConvGSCurrentWeek: false,
        roiGe1x: false,
        marginGe1: false,
        weeksInLowSampleOld: 0,
        weeksInPotentialNew: 0
    )
}

struct LabelProductDecision: Sendable, Hashable {
    var productId: String
    var previousLabel: String
    var suggestedLabel: String
    var transitionAction: String
    var reason: String
    var failHighRetain: Bool
    var marginLt1: Bool
    var noSignalRecent3: Bool
    var noConvGSCurrentWeek: Bool
    var roiGe1x: Bool
    var marginGe1: Bool
    var weeksInLowSampleOld: Int
    var weeksInPotentialNew: Int
}

struct LabelStateMachineResult: Sendable {
    var decisions: [LabelProductDecision]
    var historyNote: String
}
