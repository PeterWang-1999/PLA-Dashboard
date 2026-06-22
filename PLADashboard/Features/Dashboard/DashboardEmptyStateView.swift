import SwiftUI

struct DashboardEmptyStateView: View {
    var body: some View {
        ContentUnavailableView {
            Label("暂无产品数据", systemImage: "tray")
        } description: {
            Text("请先导入 Merchant Center、自归因报表或 Google Ads 产品数据文件。")
        } actions: {
            Button("导入数据") {}
                .buttonStyle(.borderedProminent)
        }
    }
}
