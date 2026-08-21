import SwiftUI
import UniformTypeIdentifiers

struct ProductDetailSheet: View {
    let summary: ProductPerformanceRowModel
    let reportingPeriodLabel: String?
    let loadDetail: (String) async throws -> ProductDetailModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var detail: ProductDetailModel?
    @State private var loadError: String?
    @State private var isExporting = false
    @State private var exportDocument: ProductDetailExportCSVDocument?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()

            Group {
                if let detail {
                    detailContent(detail)
                } else if let loadError {
                    ContentUnavailableView {
                        Label("无法加载产品明细", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(loadError)
                    } actions: {
                        Button("重试") { Task { await reload() } }
                            .buttonStyle(.borderedProminent)
                        Button("关闭") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                    }
                } else {
                    ProgressView("正在加载产品明细…")
                        .controlSize(.large)
                }
            }
            .padding(36)
        }
        .frame(minWidth: 860, idealWidth: 980, minHeight: 560, idealHeight: 650)
        .task(id: summary.id) { await reload() }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "product-\(summary.id)-detail"
        ) { _ in }
    }

    private func detailContent(_ detail: ProductDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            header(detail)
            hero(detail)
            Divider()
            labels(detail)
            footer(detail)
        }
    }

    private func header(_ detail: ProductDetailModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(detail.productID)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .textSelection(.enabled)
                Spacer()
                WarningLabelView(text: summary.warningLabel, style: summary.warningStyle)
                    .controlSize(.large)
            }

            Text(detail.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "未提供产品标题")
                .font(.title3.weight(.medium))
                .foregroundStyle(detail.title == nil ? .secondary : .primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func hero(_ detail: ProductDetailModel) -> some View {
        HStack(alignment: .top, spacing: 20) {
            ProductImageView(imageURL: detail.imageURL, size: 280)
                .accessibilityLabel("产品 \(detail.productID) 的图片")

            skuTable(detail)
                .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 280)
        }
    }

    private func skuTable(_ detail: ProductDetailModel) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                skuHeader("SKU", width: nil, alignment: .leading)
                skuHeader("Cost", width: 78)
                skuHeader("ROI", width: 70)
                skuHeader("Clicks", width: 74)
                skuHeader("Conv.", width: 70)
            }
            .padding(.horizontal, 12)

            if detail.skuRows.isEmpty {
                ContentUnavailableView(
                    "当前周期无 SKU 投放数据",
                    systemImage: "tablecells",
                    description: Text("该产品在当前看板周期内没有可展示的 SKU 指标。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(detail.skuRows.enumerated()), id: \.element.id) { index, row in
                            skuRow(row, isAlternate: index.isMultiple(of: 2) == false)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("SKU 表，共 \(detail.skuRows.count) 行")
    }

    private func skuHeader(
        _ title: String,
        width: CGFloat?,
        alignment: Alignment = .trailing
    ) -> some View {
        Group {
            if let width {
                Text(title).frame(width: width, alignment: alignment)
            } else {
                Text(title).frame(maxWidth: .infinity, alignment: alignment)
            }
        }
        .font(.headline)
        .foregroundStyle(.secondary)
    }

    private func skuRow(_ row: ProductDetailSKURow, isAlternate: Bool) -> some View {
        HStack(spacing: 0) {
            Text(row.itemID)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(row.itemID)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.displayCost).frame(width: 78, alignment: .trailing)
            Text(row.displayROI).frame(width: 70, alignment: .trailing)
            Text(row.displayClicks).frame(width: 74, alignment: .trailing)
            Text(row.displayConversions).frame(width: 70, alignment: .trailing)
        }
        .font(.body.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(
            isAlternate ? Color.secondary.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SKU \(row.itemID)，消费 \(row.displayCost)，ROI \(row.displayROI)，点击 \(row.displayClicks)，转化 \(row.displayConversions)")
    }

    private func labels(_ detail: ProductDetailModel) -> some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(0..<5, id: \.self) { index in
                VStack(alignment: .leading, spacing: 5) {
                    Text(detail.customLabels[index]?.nilIfEmpty ?? "—")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(detail.customLabels[index] ?? "无标签")
                    Text("自定义标签 \(index)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func footer(_ detail: ProductDetailModel) -> some View {
        HStack(spacing: 10) {
            Button("数据导出") {
                exportDocument = ProductDetailExportCSVDocument(detail: detail)
                isExporting = true
            }
            .disabled(detail.skuRows.isEmpty)

            Button("访问落地页") {
                if let url = detail.canonicalURL { openURL(url) }
            }
            .disabled(detail.canonicalURL == nil)

            if let reportingPeriodLabel {
                Text(reportingPeriodLabel)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 6)
            }

            Spacer()

            Button("关闭") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    @MainActor
    private func reload() async {
        detail = nil
        loadError = nil
        do {
            detail = try await loadDetail(summary.id)
        } catch is CancellationError {
            return
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
