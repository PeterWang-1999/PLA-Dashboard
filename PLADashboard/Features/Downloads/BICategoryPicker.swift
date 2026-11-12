import SwiftUI

struct BICategoryPicker: View {
    let categories: [BICategory]
    @Binding var filters: BIFilters

    @State private var isPresented = false
    @State private var search = ""
    @State private var firstCategoryID: String?
    @State private var secondCategoryID: String?

    private let levelTitles = ["一级品类", "二级品类", "三级品类"]

    private var selection: [BICategory] {
        if let selected = filters.selectedCategories { return selected }
        guard !filters.category.isEmpty else { return [] }
        let exact = categories.filter { $0.path == filters.category }
        let matches = exact.isEmpty ? categories.filter { $0.name == filters.category } : exact
        return matches.count == 1 ? matches : []
    }

    private var hasUnresolvedSelection: Bool {
        selection.isEmpty && !filters.category.isEmpty
    }

    private var lockedLevel: Int? { selection.first?.level }
    private var lockedLevelTitle: String? {
        guard let lockedLevel, levelTitles.indices.contains(lockedLevel - 1) else { return nil }
        return levelTitles[lockedLevel - 1]
    }

    private var summary: String {
        if hasUnresolvedSelection { return filters.category }
        if selection.count == 1, let category = selection.first { return category.path }
        if let lockedLevelTitle { return "已选 \(selection.count) 个\(lockedLevelTitle)" }
        return "全部品类"
    }

    var body: some View {
        Button {
            search = ""
            switch selection.first {
            case let category? where category.level == 1:
                firstCategoryID = category.id
                secondCategoryID = nil
            case let category? where category.level == 2:
                firstCategoryID = category.parentID
                secondCategoryID = category.id
            case let category? where category.level == 3:
                secondCategoryID = category.parentID
                firstCategoryID = categories.first { $0.id == category.parentID }?.parentID
            default:
                firstCategoryID = nil
                secondCategoryID = nil
            }
            isPresented = true
        } label: {
            BISelectionLabel(value: summary)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("品类")
        .accessibilityValue(summary)
        .help(summary)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            pickerContent
        }
    }

    private var pickerContent: some View {
        let groups = Dictionary(grouping: visibleCategories, by: \.parentID)
        return VStack(spacing: 10) {
            TextField("搜索品类", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("搜索品类")

            HStack(spacing: 0) {
                column(1, categories: groups[nil] ?? [], children: groups, activeID: firstCategoryID)
                Divider()
                column(2, categories: firstCategoryID.flatMap { groups[$0] } ?? [], children: groups, activeID: secondCategoryID)
                Divider()
                column(3, categories: secondCategoryID.flatMap { groups[$0] } ?? [], children: groups, activeID: nil)
            }
            .frame(height: 248)

            Divider()

            HStack {
                if hasUnresolvedSelection {
                    Text("原品类已不可用，请清除后重新选择。")
                        .foregroundStyle(.secondary)
                } else if let lockedLevelTitle {
                    Menu("已选 \(selection.count) 项") {
                        ForEach(selection) { category in
                            Button("移除 \(category.path)") { toggle(category, isSelected: false) }
                        }
                    }
                    .fixedSize()
                    Text("仅可勾选\(lockedLevelTitle)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("未勾选品类时导出全部品类")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("清除") { filters.selectCategories([]) }
                    .disabled(selection.isEmpty && !hasUnresolvedSelection)
                Button("完成") { isPresented = false }
            }
        }
        .padding(12)
        .frame(width: 678)
    }

    private var visibleCategories: [BICategory] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return categories }
        let byID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var visibleIDs = Set<String>()
        for category in categories where category.path.localizedStandardContains(query) {
            var node: BICategory? = category
            while let current = node, visibleIDs.insert(current.id).inserted {
                node = current.parentID.flatMap { byID[$0] }
            }
        }
        return categories.filter { visibleIDs.contains($0.id) }
    }

    private func column(
        _ level: Int, categories: [BICategory], children: [String?: [BICategory]], activeID: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(levelTitles[level - 1])
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, 8)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(categories) { category in
                        row(category, hasChildren: children[category.id] != nil, isActive: activeID == category.id)
                    }
                    if categories.isEmpty {
                        Text(level == 1 ? "没有匹配的品类" : "展开上一级品类")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
            }
            .id(level == 2 ? firstCategoryID : level == 3 ? secondCategoryID : nil)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ category: BICategory, hasChildren: Bool, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            Toggle(isOn: Binding(
                get: { selection.contains { $0.id == category.id } },
                set: { toggle(category, isSelected: $0) }
            )) {
                if !hasChildren { Text(category.name).lineLimit(1) }
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel(category.name)
            .disabled(hasUnresolvedSelection || (lockedLevel != nil && lockedLevel != category.level))

            if hasChildren {
                Button {
                    if category.level == 1 {
                        firstCategoryID = category.id
                        secondCategoryID = nil
                    } else {
                        secondCategoryID = category.id
                    }
                } label: {
                    HStack {
                        Text(category.name).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开 \(category.name)")
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(isActive ? Color.accentColor.opacity(0.14) : .clear, in: .rect(cornerRadius: 5))
        .padding(.horizontal, 2)
        .help(category.path)
    }

    private func toggle(_ category: BICategory, isSelected: Bool) {
        guard !hasUnresolvedSelection, lockedLevel == nil || lockedLevel == category.level else { return }
        var updated = selection.filter { $0.id != category.id }
        if isSelected { updated.append(category) }
        filters.selectCategories(updated)
    }
}
