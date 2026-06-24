import SwiftUI

struct DashboardToolbarContent: ToolbarContent {
    @Bindable var viewModel: DashboardViewModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            DashboardToolbarSortPicker(viewModel: viewModel)
            DashboardToolbarAlertFilterPicker(viewModel: viewModel)
            DashboardToolbarCustomLabelFilterPicker(viewModel: viewModel)
            DashboardToolbarCategoryFilter(viewModel: viewModel)
        }
    }
}
