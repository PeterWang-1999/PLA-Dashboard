import AppKit
import SwiftUI

struct BIDownloadsView: View {
    private enum Sheet: Identifiable {
        case connection
        case export
        case schedule(BISchedule?)
        case detail(UUID)

        var id: String {
            switch self {
            case .connection: "connection"
            case .export: "export"
            case .schedule(let task): task?.id.uuidString ?? "new-schedule"
            case .detail(let id): id.uuidString
            }
        }
    }

    @Environment(BIDownloadStore.self) private var store
    @State private var sheet: Sheet?

    let accountID: String

    private var workspace: BIWorkspace { store.workspace(accountID) }
    private var connected: Bool { store.connectedAccounts.contains(accountID) }
    private var isConnecting: Bool { store.busyAccount == accountID && !connected }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                connectionHeader
                if !connected {
                    BIStatusNotice(
                        title: "登录后开始下载",
                        detail: "在应用中连接 BI Data，登录成功后会保留会话。",
                        symbol: "person.crop.circle.badge.exclamationmark",
                        tint: .orange
                    )
                }
                schedules
                history
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("数据下载")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("编辑任务") {
                    Button("新建定时任务") { sheet = .schedule(nil) }
                    ForEach(workspace.schedules) { task in
                        Button("编辑 \(task.name)") { sheet = .schedule(task) }
                    }
                }
                .disabled(!connected)
                .help("新建或编辑定时下载任务")
            }
            if #available(macOS 26.0, *) {
                ToolbarSpacer(.fixed, placement: .primaryAction)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("临时导出") { sheet = .export }
                    .disabled(!connected)
            }
        }
        .task(id: accountID) { store.checkConnection(accountID) }
        .sheet(item: $sheet) { item in
            switch item {
            case .connection:
                BIConnectionSheet(accountID: accountID, portal: workspace.portal)
            case .export:
                BIExportSheet(accountID: accountID, presets: workspace.effectivePresets)
            case .schedule(let task):
                BIScheduleSheet(accountID: accountID, task: task, presets: workspace.effectivePresets)
            case .detail(let id):
                if let run = workspace.runs.first(where: { $0.id == id }) {
                    BIRunDetailSheet(accountID: accountID, run: run, canRetry: connected)
                }
            }
        }
        .alert("BI Data", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var connectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("BI Data").font(.title.bold()).accessibilityAddTraits(.isHeader)
                Text("渠道投放分析 · 投放产品明细").foregroundStyle(.secondary)
            }
            Spacer()
            if connected {
                BIStatusLabel(title: "已登录", symbol: "checkmark.circle.fill", tint: .green)
            } else if isConnecting {
                ProgressView().controlSize(.small)
                Text("正在连接").foregroundStyle(.secondary)
            } else {
                BIStatusLabel(title: "需要登录", symbol: "exclamationmark.circle", tint: .orange)
                Button("登录 BI Data…") { sheet = .connection }
                    .disabled(store.busyAccount != nil)
            }
        }
    }

    private var schedules: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("定时下载").font(.headline).accessibilityAddTraits(.isHeader)
            if workspace.schedules.isEmpty {
                BIStatusNotice(
                    title: "暂无定时任务",
                    detail: connected ? "在「编辑任务」菜单中创建定时下载。" : "登录 BI Data 后，即可选择预设并创建定时下载。",
                    symbol: "clock"
                )
            } else {
                ForEach(workspace.schedules) { task in
                    scheduleCard(task)
                }
            }
        }
    }

    private func scheduleCard(_ task: BISchedule) -> some View {
        let preset = workspace.effectivePresets.first { $0.id == task.presetID }
        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name).font(.headline)
                    Text("渠道投放分析 · 投放产品明细")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    Text("每天 \(task.timeLabel)（北京时间） · \(preset?.filters.rangeRule ?? "预设不可用")")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
                Spacer(minLength: 12)
                Toggle("启用 \(task.name)", isOn: Binding(
                    get: { task.enabled },
                    set: { value in
                        var updated = task
                        updated.enabled = value
                        store.saveSchedule(updated, accountID: accountID)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                Button("立即运行") {
                    if let preset { store.enqueue(preset.filters, origin: .scheduled, accountID: accountID) }
                }
                .disabled(!connected || preset == nil)
            }
            if let next = task.nextRun {
                Text("下次运行  \(next.formatted(BIDateText.schedule))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("已暂停").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .biDownloadCard()
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("下载记录").font(.headline).accessibilityAddTraits(.isHeader)
            if workspace.runs.isEmpty {
                BIStatusNotice(title: "暂无下载记录", detail: "首次提交导出后，可以在这里查看进度并打开 CSV。", symbol: "tray")
            } else {
                Table(workspace.runs) {
                    TableColumn("报表 / 来源") { run in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(run.reportKind.rawValue).fontWeight(.medium)
                                Text(run.origin.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            if run.reportKind == .productDetail, let category = run.filters.categoryLabel {
                                Text(category).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(category)
                            }
                        }
                    }
                    .width(min: 125, ideal: 235)
                    TableColumn("报表周") { run in
                        Text(run.filters.weekLabel).font(.subheadline)
                    }
                    .width(min: 78, ideal: 130)
                    TableColumn("状态") { run in
                        BIStatusLabel(status: run.status)
                    }
                    .width(min: 72, ideal: 98)
                    TableColumn("创建时间") { run in
                        Text(run.submittedAt.formatted(BIDateText.history)).foregroundStyle(.secondary)
                    }
                    .width(min: 76, ideal: 96)
                    TableColumn("操作") { run in
                        Button(actionTitle(run)) { open(run) }
                            .buttonStyle(.link)
                    }
                    .width(min: 66, ideal: 86)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .environment(\.defaultMinListRowHeight, 36)
                .frame(height: 31 + CGFloat(min(workspace.runs.count, 8)) * 36)
                .clipShape(.rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color(nsColor: .separatorColor)) }
            }
        }
    }

    private func actionTitle(_ run: BIDownloadRun) -> String {
        switch run.status {
        case .completed: run.reportKind.openTitle
        case .failed, .connectionFailed, .needsLogin: "查看原因"
        default: "查看进度"
        }
    }

    private func open(_ run: BIDownloadRun) {
        guard run.status == .completed else {
            sheet = .detail(run.id)
            return
        }
        guard let source = store.downloadURL(for: run, accountID: accountID),
              FileManager.default.fileExists(atPath: source.path) else {
            store.errorMessage = "找不到这份报表，可在 BI Data 中重新导出。"
            return
        }
        let url: URL
        var copyError: String?
        do {
            url = try BIDownloadStore.copyToDownloads(source, for: run)
        } catch {
            url = source
            copyError = "无法复制报表到「下载」。\(error.localizedDescription)"
        }
        if NSWorkspace.shared.open(url) {
            store.errorMessage = copyError
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            store.errorMessage = [copyError, "无法使用默认应用打开报表，已在 Finder 中定位文件。"]
                .compactMap { $0 }.joined(separator: "\n")
        }
    }
}

struct BIStatusNotice: View {
    let title: String
    let detail: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .biDownloadCard()
    }
}

private extension View {
    func biDownloadCard() -> some View {
        padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.055), in: .rect(cornerRadius: 20))
    }
}

struct BIStatusLabel: View {
    let title: String
    let symbol: String
    let tint: Color

    init(title: String, symbol: String, tint: Color) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
    }

    init(status: BIDownloadRun.Status) {
        switch status {
        case .queued: self.init(title: "排队中", symbol: "clock", tint: .secondary)
        case .submitting: self.init(title: "提交中", symbol: "arrow.up.circle", tint: .blue)
        case .generating: self.init(title: "生成中", symbol: "clock", tint: .blue)
        case .downloading: self.init(title: "下载中", symbol: "arrow.down.circle", tint: .blue)
        case .completed: self.init(title: "已下载", symbol: "checkmark.circle.fill", tint: .green)
        case .needsLogin: self.init(title: "需要登录", symbol: "exclamationmark.circle", tint: .orange)
        case .connectionFailed: self.init(title: "连接失败", symbol: "exclamationmark.circle", tint: .orange)
        case .failed: self.init(title: "下载失败", symbol: "exclamationmark.circle", tint: .orange)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            Text(title)
        }
        .font(.subheadline)
    }
}

enum BIDateText {
    static let schedule = style(.dateTime.month().day().hour().minute())
    static let history = style(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
    static let day = style(.dateTime.month(.twoDigits).day(.twoDigits))

    private static func style(_ value: Date.FormatStyle) -> Date.FormatStyle {
        var value = value
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = BIReportCalendar.timeZone
        return value
    }
}
