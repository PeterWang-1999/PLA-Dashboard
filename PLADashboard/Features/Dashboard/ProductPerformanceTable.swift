import SwiftUI

struct ProductPerformanceTable: View {
    let rows: [ProductPerformanceRowModel]
    let visibleColumns: [DashboardColumn]

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(rows) { row in
                        ProductPerformanceRowView(row: row, visibleColumns: visibleColumns)
                        Divider()
                    }
                } header: {
                    ProductPerformanceHeaderView(visibleColumns: visibleColumns)
                    Divider()
                }
            }
        }
        .background(Color(.textBackgroundColor))
    }
}

private struct ProductPerformanceHeaderView: View {
    let visibleColumns: [DashboardColumn]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(visibleColumns) { column in
                Text(column.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: column.width, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 25, alignment: .center)
        .background(Color(.windowBackgroundColor))
    }
}

struct ProductPerformanceRowView: View {
    let row: ProductPerformanceRowModel
    let visibleColumns: [DashboardColumn]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(visibleColumns) { column in
                cell(for: column)
                    .frame(width: column.width, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 50, alignment: .center)
    }

    @ViewBuilder
    private func cell(for column: DashboardColumn) -> some View {
        switch column {
        case .lsin:
            Text(row.lsin)
                .font(.system(size: 13))
        case .productImage:
            ProductImageView(imageURL: row.imageURL)
        case .cost:
            VStack(alignment: .leading, spacing: 2) {
                Text(row.cost).font(.system(size: 13))
                Text(row.costShare).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .roi:
            Text(row.roi).font(.system(size: 13))
        case .warningLabel:
            WarningLabelView(text: row.warningLabel, style: row.warningStyle)
        case .costTrend, .gsTrend:
            TrendPlaceholderView()
        case .cpa:
            MetricDeltaCell(value: row.cpa, delta: row.cpaDelta)
        case .arpu:
            MetricDeltaCell(value: row.arpu, delta: row.arpuDelta)
        case .cpc:
            MetricDeltaCell(value: row.cpc, delta: row.cpcDelta)
        case .cvr:
            MetricDeltaCell(value: row.cvr, delta: row.cvrDelta)
        case .aos:
            MetricDeltaCell(value: row.aos, delta: row.aosDelta)
        case .clicks:
            Text(row.clicks ?? "—").font(.system(size: 13))
        case .conversions:
            Text(row.conversions ?? "—").font(.system(size: 13))
        }
    }
}
