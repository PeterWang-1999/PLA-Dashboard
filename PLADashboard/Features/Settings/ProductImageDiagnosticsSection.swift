import SwiftUI

struct ProductImageDiagnosticsSection: View {
    @Environment(AccountStore.self) private var accountStore

    let accountID: String
    let accountName: String

    @State private var isRunning = false
    @State private var reportText: String?
    @State private var showReport = false
    @State private var actionMessage: String?

    var body: some View {
        Section {
            Button {
                Task { await runDiagnostics() }
            } label: {
                if isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在诊断…")
                    }
                } else {
                    Text("诊断产品图数据…")
                }
            }
            .disabled(isRunning)

            if let client = accountStore.activeDatabaseClient, client.accountID == accountID {
                Button("合并 S 前缀产品记录") {
                    Task { await reconcilePrefixedProducts(client: client) }
                }
                .disabled(isRunning)
            }

            if let reportText {
                Text(reportText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            Text("产品图")
        } footer: {
            Text("检查当前账户的图片链接入库情况、S 前缀 ID 对齐与 URL 格式。若看板图片持续加载，请确认图片域名在本机可访问。")
        }
        .alert("产品图诊断", isPresented: $showReport) {
            Button("好", role: .cancel) {}
        } message: {
            Text(actionMessage ?? reportText ?? "")
        }
    }

    @MainActor
    private func reconcilePrefixedProducts(client: DatabaseClient) async {
        isRunning = true
        defer { isRunning = false }

        do {
            try await client.reconcileLsinPrefixedProductIDs()
            let report = try await client.buildProductImageDiagnosticsReport(accountName: accountName)
            reportText = report.formattedText
            actionMessage = "已尝试合并 S 前缀产品记录。"
            showReport = true
        } catch {
            actionMessage = error.localizedDescription
            showReport = true
        }
    }

    @MainActor
    private func runDiagnostics() async {
        guard let client = accountStore.activeDatabaseClient,
              client.accountID == accountID else {
            reportText = "数据库未就绪"
            showReport = true
            return
        }

        isRunning = true
        defer { isRunning = false }

        do {
            let report = try await client.buildProductImageDiagnosticsReport(accountName: accountName)
            reportText = report.formattedText
        } catch {
            reportText = error.localizedDescription
            showReport = true
        }
    }
}
