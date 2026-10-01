import SwiftUI

struct ProductImageView: View {
    let imageURL: URL?
    var size: CGFloat = 40

    @Environment(\.displayScale) private var displayScale
    @State private var loadedImage: NSImage?
    @State private var loadedTaskID: String?
    @State private var operationID = UUID()
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var reloadToken = 0

    var body: some View {
        Group {
            if let loadedImage, loadedTaskID == loadTaskID {
                Image(nsImage: loadedImage)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("产品图片")
            } else if isLoading {
                Image(systemName: "photo")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.quaternarySystemFill))
                    .overlay {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    .accessibilityLabel("正在加载产品图片")
            } else if loadFailed {
                failurePlaceholder
            } else if imageURL != nil {
                Image(systemName: "photo")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.quaternarySystemFill))
                    .accessibilityLabel("产品图片")
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(6, size * 0.1), style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: max(6, size * 0.1), style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
        }
        .task(id: loadTaskID) {
            await loadImageIfNeeded()
        }
    }

    private var loadTaskID: String {
        guard let imageURL else { return "nil" }
        return "\(imageURL.absoluteString)|\(reloadToken)|\(pixelSize)"
    }

    private var failurePlaceholder: some View {
        VStack(spacing: 2) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("重试") {
                loadedImage = nil
                loadFailed = false
                reloadToken += 1
            }
            .buttonStyle(.plain)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("重试加载产品图片")
            .accessibilityHint("重新下载此产品的图片")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.quaternarySystemFill))
        .accessibilityElement(children: .contain)
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.quaternarySystemFill))
            .accessibilityLabel("无产品图片")
    }

    private var pixelSize: Int { max(1, min(Int(ceil(size * displayScale)), 4_096)) }

    @MainActor
    private func loadImageIfNeeded() async {
        let operation = UUID()
        operationID = operation
        let taskID = loadTaskID
        loadedImage = nil
        loadedTaskID = nil
        loadFailed = false
        isLoading = imageURL != nil
        defer { if operationID == operation { isLoading = false } }
        guard let imageURL else { return }
        do {
            let thumbnail = try await ProductImageLoader.shared.loadThumbnail(
                from: imageURL, maxPixelSize: pixelSize, reloadToken: reloadToken
            )
            guard !Task.isCancelled, operationID == operation else { return }
            loadedImage = NSImage(cgImage: thumbnail.image, size: NSSize(
                width: CGFloat(thumbnail.image.width) / displayScale,
                height: CGFloat(thumbnail.image.height) / displayScale
            ))
            loadedTaskID = taskID
        } catch {
            guard !Task.isCancelled, operationID == operation else { return }
            loadFailed = true
        }
    }

}

#Preview {
    ProductImageView(
        imageURL: URL(string: "https://cdn.shopify.com/s/files/1/0887/9364/5331/files/svybxx1779861145029.jpg?v=1780033180")
    )
    .padding()
}
