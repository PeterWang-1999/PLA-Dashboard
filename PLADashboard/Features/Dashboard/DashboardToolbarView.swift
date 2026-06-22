import SwiftUI

struct DashboardToolbarContent: ToolbarContent {
    @Bindable var viewModel: DashboardViewModel

    var body: some ToolbarContent {
        ToolbarItem(id: "alert-filter", placement: .primaryAction) {
            DashboardToolbarAlertFilterPicker(viewModel: viewModel)
        }
        ToolbarItem(id: "custom-label-filter", placement: .primaryAction) {
            DashboardToolbarCustomLabelFilterPicker(viewModel: viewModel)
        }
        ToolbarItem(id: "category-filter", placement: .primaryAction) {
            DashboardToolbarCategoryFilter(viewModel: viewModel)
        }
        ToolbarItem(id: "search", placement: .primaryAction) {
            DashboardSearchField(text: $viewModel.searchText)
        }
    }
}
