import SwiftUI

struct DashboardEmptyStateView: View {
    var onImport: () -> Void = {}

    var body: some View {
        ContentUnavailableView {
            Label("暂无产品数据", systemImage: "tray")
        } description: {
            Text("请先导入 Merchant Center 与投放数据（三方站：Google Ads；自建站：投放产品明细），然后刷新聚合。")
        } actions: {
            Button("导入数据", action: onImport)
                .buttonStyle(.borderedProminent)
        }
    }
}

#Preview("Empty State") {
    NavigationStack {
        DashboardEmptyStateView()
            .navigationTitle("产品数据")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack {
                    Spacer()
                    Button("快捷操作") {}
                        .buttonStyle(.bordered)
                }
                .padding()
                .background(.bar)
            }
    }
    .frame(width: 783, height: 620)
}

#Preview {
    DashboardEmptyStateView()
        .frame(width: 480, height: 320)
}
