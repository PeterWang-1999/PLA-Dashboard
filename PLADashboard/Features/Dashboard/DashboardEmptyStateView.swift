import SwiftUI

struct DashboardEmptyStateView: View {
    var accountKind: WorkspaceAccountKind = .thirdParty
    var onImport: () -> Void = {}

    var body: some View {
        ContentUnavailableView {
            Label("暂无产品数据", systemImage: "tray")
        } description: {
            if accountKind == .selfBuilt {
                Text("导入 Merchant Center 商品资料，并从底栏「数据维护 → 同步数据」获取 BI Data 投放产品明细。")
            } else {
                Text("请先导入 Merchant Center 和 Google Ads 数据，然后刷新聚合。")
            }
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
