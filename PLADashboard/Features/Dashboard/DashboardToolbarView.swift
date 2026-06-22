import SwiftUI

struct DashboardToolbarView: View {
    @Bindable var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("产品数据")
                .font(.system(size: 15, weight: .semibold))

            Spacer(minLength: 16)

            Picker("时间维度", selection: $viewModel.selectedTimeDimension) {
                Text("周维度").tag("周维度")
                Text("月维度").tag("月维度")
            }
            .pickerStyle(.menu)
            .frame(minWidth: 100)

            Picker("账户", selection: $viewModel.selectedAccount) {
                Text("全部账户").tag("全部账户")
                Text("US").tag("US")
                Text("GB").tag("GB")
            }
            .pickerStyle(.menu)
            .frame(minWidth: 110)

            Picker("标签", selection: $viewModel.selectedTag) {
                Text("全部标签").tag("全部标签")
                Text("自定义标签 0").tag("自定义标签 0")
                Text("自定义标签 1").tag("自定义标签 1")
            }
            .pickerStyle(.menu)
            .frame(minWidth: 120)
        }
        .frame(height: 56)
        .padding(.horizontal, 10)
    }
}
