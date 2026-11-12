import AppKit
import SwiftUI
import WebKit

private struct BIFormSheet<Content: View, Actions: View>: View {
    let title: String
    let subtitle: String?
    let width: CGFloat
    @ViewBuilder var content: Content
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
            }
            content
            Divider()
            HStack(spacing: 8) {
                Spacer()
                actions
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 19)
        .frame(width: width)
    }
}

private struct BIFormRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Text(title).frame(width: 88, alignment: .leading)
            content
            Spacer(minLength: 0)
        }
    }
}

private struct BISearchableSelection: View {
    let title: String
    let choices: [String]
    var allLabel: String?
    @Binding var selection: String
    @State private var isPresented = false
    @State private var search = ""
    @FocusState private var isSearchFocused: Bool

    private var visibleChoices: [String] {
        search.isEmpty ? choices : choices.filter { $0.localizedStandardContains(search) }
    }

    var body: some View {
        Button {
            search = ""
            isPresented = true
        } label: {
            HStack {
                Text(selection.isEmpty ? allLabel ?? title : selection)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(title)
        .accessibilityValue(selection.isEmpty ? allLabel ?? "" : selection)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("搜索\(title)", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .focused($isSearchFocused)
                List {
                    if let allLabel, search.isEmpty {
                        choiceButton(allLabel, value: "")
                    }
                    ForEach(visibleChoices, id: \.self) { choice in
                        choiceButton(choice, value: choice)
                    }
                    if visibleChoices.isEmpty && (allLabel == nil || !search.isEmpty) {
                        Text("没有匹配的选项").foregroundStyle(.secondary)
                    }
                }
                .listStyle(.plain)
            }
            .padding(12)
            .frame(width: 360, height: 300)
            .defaultFocus($isSearchFocused, true)
        }
    }

    private func choiceButton(_ label: String, value: String) -> some View {
        Button {
            selection = value
            isPresented = false
        } label: {
            HStack {
                Text(label)
                Spacer()
                if selection == value {
                    Image(systemName: "checkmark").accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
    }
}

struct BIExportSheet: View {
    private struct OptionsRequest: Equatable {
        let merchant: String?
        let attempt: Int
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(BIDownloadStore.self) private var store
    @State private var presetID = BIPreset.standard.id
    @State private var filters = BIPreset.standard.filters
    @State private var customRange = false
    @State private var firstWeek = ""
    @State private var lastWeek = ""
    @State private var showSavePreset = false
    @State private var isLoadingOptions = true
    @State private var optionsError: String?
    @State private var optionsRefresh = 0

    let accountID: String
    let presets: [BIPreset]
    private let weeks = BIReportCalendar.weeks(through: .now, count: 104)
    private var options: BIFilterOptions { store.workspace(accountID).options }
    private var availableWeeks: [String] { options.reportWeeks ?? weeks.map(\.id) }
    private var optionsRequest: OptionsRequest { OptionsRequest(merchant: filters.merchant, attempt: optionsRefresh) }

    private var draft: BIFilters {
        var result = filters
        result.firstWeek = customRange ? firstWeek : nil
        result.lastWeek = customRange ? lastWeek : nil
        return result
    }

    private var valid: Bool {
        !filters.dimensions.isEmpty && (!customRange || (
            firstWeek <= lastWeek && availableWeeks.contains(firstWeek) && availableWeeks.contains(lastWeek)
        ))
    }

    var body: some View {
        BIFormSheet(title: "临时导出", subtitle: "从预设填入筛选条件。更改仅用于本次导出。", width: 576) {
            VStack(spacing: 9) {
                BIFormRow(title: "筛选预设") {
                    Picker("筛选预设", selection: $presetID) {
                        ForEach(presets) { preset in Text(preset.name).tag(preset.id) }
                    }
                    .labelsHidden()
                    .frame(width: 286, alignment: .leading)
                    Button("另存为预设…") { showSavePreset = true }
                        .buttonStyle(.link)
                        .disabled(!valid)
                }
                BIFormRow(title: "报表") { Text("渠道投放分析") }
            }
            Divider()
            if isLoadingOptions {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在加载筛选项…").foregroundStyle(.secondary)
                }
            } else if let optionsError {
                HStack {
                    Text(optionsError).foregroundStyle(.secondary)
                    if store.connectedAccounts.contains(accountID) {
                        Button("重试") { optionsRefresh += 1 }
                    }
                }
            }
            VStack(spacing: 9) {
                filterPicker("商户", selection: Binding(
                    get: { filters.merchant ?? "" },
                    set: { merchant in
                        filters.merchant = merchant.isEmpty ? nil : merchant
                        filters.category = ""
                    }
                ), values: options.merchants ?? [], all: "BI Data 默认商户")
                filterPicker("渠道分组", selection: $filters.channel, values: options.channels, all: "全部渠道")
                BIFormRow(title: "分类方式") {
                    Picker("分类方式", selection: Binding(
                        get: { filters.classificationMode },
                        set: { mode in
                            filters.classification = mode
                            switch mode {
                            case .businessUnit: filters.category = ""
                            case .category: filters.businessUnit = ""
                            }
                        }
                    )) {
                        Text("BU").tag(BIClassification.businessUnit)
                        Text("品类").tag(BIClassification.category)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                switch filters.classificationMode {
                case .businessUnit:
                    filterPicker("BU", selection: $filters.businessUnit, values: options.businessUnits, all: "全部 BU")
                case .category:
                    BIFormRow(title: "品类") {
                        BISearchableSelection(
                            title: "品类", choices: options.categories, allLabel: "全部品类", selection: $filters.category
                        )
                        .frame(width: 286, alignment: .leading)
                        .disabled(isLoadingOptions || optionsError != nil)
                    }
                }
                BIFormRow(title: "国家") {
                    BISearchableSelection(
                        title: "国家", choices: options.countries, allLabel: "全部国家", selection: $filters.country
                    )
                    .frame(width: 286, alignment: .leading)
                }
                BIFormRow(title: "时间范围") {
                    Picker("时间范围", selection: $customRange) {
                        Text("过去 6 个完整周 + 本周").tag(false)
                        Text("自定义周范围").tag(true)
                    }
                    .labelsHidden()
                    .frame(width: 286, alignment: .leading)
                }
                if customRange {
                    BIFormRow(title: "起止周") {
                        weekPicker("起始周", selection: $firstWeek)
                        Text("至").foregroundStyle(.secondary)
                        weekPicker("结束周", selection: $lastWeek)
                    }
                }
                BIFormRow(title: "") {
                    Text(rangeSummary)
                        .font(.caption)
                        .foregroundStyle(valid ? Color.secondary : Color.orange)
                }
                BIFormRow(title: "展开维度") {
                    ForEach(BIDimension.allCases) { dimension in
                        Toggle(dimension.rawValue, isOn: Binding(
                            get: { filters.dimensions.contains(dimension) },
                            set: { selected in
                                if selected { filters.dimensions.insert(dimension) }
                                else { filters.dimensions.remove(dimension) }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }
        } actions: {
            Button("取消", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("开始导出") {
                if store.enqueue(draft, origin: .manual, accountID: accountID) { dismiss() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!valid || !store.connectedAccounts.contains(accountID))
        }
        .task(id: optionsRequest) {
            let request = optionsRequest
            isLoadingOptions = true
            optionsError = nil
            defer {
                if optionsRequest == request { isLoadingOptions = false }
            }
            do {
                try await store.refreshFilterOptions(for: accountID, merchant: request.merchant)
            } catch {
                guard !Task.isCancelled else { return }
                optionsError = error.localizedDescription
            }
        }
        .onAppear(perform: applyPreset)
        .onChange(of: presetID) { _, _ in applyPreset() }
        .sheet(isPresented: $showSavePreset) {
            BIPresetSheet(accountID: accountID, filters: draft)
        }
    }

    private func applyPreset() {
        filters = presets.first(where: { $0.id == presetID })?.filters ?? BIFilters()
        customRange = filters.firstWeek != nil && filters.lastWeek != nil
        let range = filters.resolved(through: .now)
        firstWeek = range.firstWeek ?? ""
        lastWeek = range.lastWeek ?? ""
    }

    private var rangeSummary: String {
        guard !filters.dimensions.isEmpty else { return "请至少选择一个展开维度。" }
        if customRange && (!availableWeeks.contains(firstWeek) || !availableWeeks.contains(lastWeek)) {
            return "请选择 BI Data 提供的起止周。"
        }
        guard valid else { return "结束周须等于或晚于起始周。" }
        let resolved = draft.resolved(through: .now)
        guard let start = weeks.first(where: { $0.id == resolved.firstWeek }),
              let end = weeks.first(where: { $0.id == resolved.lastWeek }) else { return resolved.weekLabel }
        let count = (BIReportCalendar.calendar.dateComponents([.weekOfYear], from: start.start, to: end.start).weekOfYear ?? 0) + 1
        let current = end.id == weeks.first?.id ? " · 含本周" : ""
        return "\(start.start.formatted(BIDateText.day))–\(end.end.formatted(BIDateText.day)) · \(count) 个报表周\(current)"
    }

    private func filterPicker(_ name: String, selection: Binding<String>, values: [String], all: String) -> some View {
        let selected = selection.wrappedValue
        let choices = Set(values + [selected]).filter { !$0.isEmpty }.sorted()
        return BIFormRow(title: name) {
            Picker(name, selection: selection) {
                Text(all).tag("")
                ForEach(choices, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 286, alignment: .leading)
        }
    }

    private func weekPicker(_ name: String, selection: Binding<String>) -> some View {
        BISearchableSelection(title: name, choices: availableWeeks, selection: selection)
            .frame(width: 128, alignment: .leading)
    }
}

private struct BIPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BIDownloadStore.self) private var store
    @State private var name = ""

    let accountID: String
    let filters: BIFilters

    var body: some View {
        BIFormSheet(title: "另存为预设", subtitle: "将当前筛选保存到这个自建站工作区。", width: 460) {
            BIFormRow(title: "预设名称") {
                TextField("预设名称", text: $name, prompt: Text("输入名称"))
                    .labelsHidden()
            }
        } actions: {
            Button("取消", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("保存预设") {
                if store.savePreset(BIPreset(name: trimmedName, filters: filters), accountID: accountID) {
                    dismiss()
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(trimmedName.isEmpty)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct BIScheduleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BIDownloadStore.self) private var store
    @State private var draft: BISchedule
    @State private var time: Date
    @FocusState private var isNameFocused: Bool

    let accountID: String
    let presets: [BIPreset]
    let isEditing: Bool

    init(accountID: String, task: BISchedule?, presets: [BIPreset]) {
        self.accountID = accountID
        self.presets = presets
        self.isEditing = task != nil
        let draft = task ?? BISchedule()
        _draft = State(initialValue: draft)
        _time = State(initialValue: BIReportCalendar.occurrence(
            hour: draft.hour, minute: draft.minute, near: .now, next: true
        ) ?? .now)
    }

    var body: some View {
        BIFormSheet(
            title: isEditing ? "编辑定时任务" : "新建定时任务",
            subtitle: nil,
            width: 540
        ) {
            Form {
                Section {
                    TextField("任务名称", text: $draft.name)
                        .focused($isNameFocused)
                    Picker("筛选预设", selection: $draft.presetID) {
                        if preset == nil {
                            Text("预设不可用").tag(draft.presetID)
                        }
                        ForEach(presets) { preset in Text(preset.name).tag(preset.id) }
                    }
                    .pickerStyle(.menu)
                    LabeledContent("报表", value: "渠道投放分析、投放产品明细")
                } header: {
                    Text("下载内容")
                } footer: {
                    if let filters = preset?.filters {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("报表周 · \(filters.rangeRule)")
                            if !filters.supportsProductDetail {
                                Text("投放产品明细仅支持 Google PLA，请选择对应的筛选预设。")
                                    .foregroundStyle(.orange)
                            }
                            if filters.firstWeek == nil, let nextRun {
                                Text("下次下载范围 · \(filters.resolved(through: nextRun).weekLabel)")
                            }
                        }
                    }
                }

                Section {
                    DatePicker("每天运行时间", selection: $time, displayedComponents: .hourAndMinute)
                        .environment(\.timeZone, BIReportCalendar.timeZone)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    Toggle("启用任务", isOn: $draft.enabled)
                        .toggleStyle(.switch)
                } header: {
                    Text("运行计划 · 北京时间")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let nextRun {
                            Text("下次运行 · \(nextRun.formatted(BIDateText.schedule))")
                        }
                        Text("定时下载在应用运行期间执行。")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(height: 340)
        } actions: {
            Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
            Button(isEditing ? "保存任务" : "创建任务") {
                var schedule = draft
                schedule.name = trimmedName
                schedule.hour = hour
                schedule.minute = minute
                if store.saveSchedule(schedule, accountID: accountID) { dismiss() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(trimmedName.isEmpty || preset?.filters.supportsProductDetail != true)
        }
        .defaultFocus($isNameFocused, true)
    }

    private var preset: BIPreset? { presets.first { $0.id == draft.presetID } }
    private var nextRun: Date? {
        guard draft.enabled else { return nil }
        return BIReportCalendar.occurrence(hour: hour, minute: minute, near: .now, next: true)
    }
    private var hour: Int { BIReportCalendar.calendar.component(.hour, from: time) }
    private var minute: Int { BIReportCalendar.calendar.component(.minute, from: time) }
    private var trimmedName: String { draft.name.trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct BIConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(BIDownloadStore.self) private var store
    @State private var address: String
    @State private var session: BIWebSession?
    @State private var message: String?
    @State private var openedInitialAddress = false
    @State private var zoomPercent = 80

    let accountID: String

    init(accountID: String, portal: URL?) {
        self.accountID = accountID
        _address = State(initialValue: portal?.absoluteString ?? "http://data.litb.cn:8081/#")
    }

    var body: some View {
        if let session {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("连接 BI Data").font(.headline)
                        Text("使用公司账号登录，成功后将自动返回「数据下载」。")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("更改地址") {
                        self.session = nil
                        message = nil
                    }
                    Button("在默认浏览器打开") { openURL(session.portal) }
                }
                .padding(16)
                Divider()
                BILoginWebView(session: session, zoom: Double(zoomPercent) / 100)
                    .frame(minHeight: 480)
                Divider()
                HStack(spacing: 10) {
                    Button {
                        zoomPercent -= 10
                    } label: {
                        Image(systemName: "minus")
                    }
                    .accessibilityLabel("缩小登录页面")
                    .disabled(zoomPercent <= 50)
                    Button("\(zoomPercent)%") { zoomPercent = 100 }
                        .help("还原网页缩放")
                        .accessibilityLabel("网页缩放 \(zoomPercent)%，点击还原")
                    Button {
                        zoomPercent += 10
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("放大登录页面")
                    .disabled(zoomPercent >= 120)
                    if let message { Text(message).font(.subheadline).foregroundStyle(.secondary) }
                    Spacer()
                    Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                }
                .padding(14)
            }
            .frame(minWidth: 800, idealWidth: 1000)
            .task(id: ObjectIdentifier(session)) {
                while !Task.isCancelled {
                    if (try? await session.isAuthenticated()) == true {
                        guard !Task.isCancelled else { return }
                        do {
                            try store.saveConnection(accountID, portal: session.portal)
                            dismiss()
                        } catch {
                            message = error.localizedDescription
                        }
                        return
                    }
                    do { try await Task.sleep(for: .seconds(2)) }
                    catch { return }
                }
            }
        } else {
            BIFormSheet(title: "更改 BI Data 地址", subtitle: "继续后将在应用中打开此地址。", width: 520) {
                BIFormRow(title: "BI Data 地址") {
                    TextField("BI Data 地址", text: $address, prompt: Text("粘贴浏览器地址"))
                        .labelsHidden()
                    PasteButton(payloadType: String.self) { values in
                        if let value = values.first { address = value }
                    }
                }
                if let message { Text(message).foregroundStyle(.secondary) }
            } actions: {
                Button("取消", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("继续") { begin() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .onAppear {
                guard !openedInitialAddress else { return }
                openedInitialAddress = true
                begin()
            }
        }
    }

    private func begin() {
        do {
            session = try store.loginSession(accountID, address: address)
            message = nil
        } catch {
            message = error.localizedDescription
        }
    }

}

private struct BILoginWebView: NSViewRepresentable {
    let session: BIWebSession
    let zoom: Double

    func makeNSView(context: Context) -> WKWebView { session.webView }
    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
    }
}

struct BIRunDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BIDownloadStore.self) private var store
    let accountID: String
    let run: BIDownloadRun
    let canRetry: Bool

    private var failed: Bool { [.failed, .connectionFailed, .needsLogin].contains(run.status) }

    var body: some View {
        BIFormSheet(
            title: failed ? "任务详情" : "导出进度",
            subtitle: "\(run.submittedAt.formatted(BIDateText.schedule)) · 北京时间",
            width: 486
        ) {
            VStack(spacing: 9) {
                BIFormRow(title: "报表") { Text(run.reportKind.rawValue) }
                BIFormRow(title: "来源") { Text(run.origin.rawValue) }
                BIFormRow(title: "报表周") { Text(run.filters.weekLabel) }
                BIFormRow(title: "状态") { BIStatusLabel(status: run.status) }
            }
            if failed {
                BIStatusNotice(
                    title: run.status == .needsLogin ? "请重新登录 BI Data" : "此任务未完成",
                    detail: run.detail ?? "可按原筛选条件重试。",
                    symbol: run.status == .connectionFailed ? "wifi.slash" : "exclamationmark.circle",
                    tint: .orange
                )
            } else if run.status != .completed {
                BIStatusNotice(
                    title: progressTitle,
                    detail: "就绪后会自动下载，关闭此窗口可继续等待。",
                    symbol: "clock",
                    tint: .blue
                )
            }
        } actions: {
            Button(failed ? "关闭" : "完成") { dismiss() }.keyboardShortcut(.cancelAction)
            if failed && canRetry {
                Button("重试") {
                    store.retry(run.id, accountID: accountID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var progressTitle: String {
        switch run.status {
        case .queued: "正在等待提交"
        case .submitting: "正在提交到 BI Data"
        case .generating: "正在等待 BI Data 生成文件"
        default: "下载任务进行中"
        }
    }
}
