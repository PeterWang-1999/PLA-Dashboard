import SwiftUI

struct ProductImageView: View {
    let imageURL: URL?

    @State private var loadedImage: NSImage?
    @State private var isLoading = false
    @State private var loadFailed = false
    @State private var reloadToken = 0

    var body: some View {
        Group {
            if let loadedImage {
                Image(nsImage: loadedImage)
                    .resizable()
                    .scaledToFill()
            } else if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else if loadFailed {
                failurePlaceholder
            } else if imageURL != nil {
                ProgressView()
                    .controlSize(.small)
            } else {
                placeholder
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .task(id: loadTaskID) {
            await loadImageIfNeeded()
        }
    }

    private var loadTaskID: String {
        guard let imageURL else { return "nil" }
        return "\(imageURL.absoluteString)|\(reloadToken)"
    }

    private var accessibilityLabelText: String {
        if loadFailed {
            return "产品图片加载失败"
        }
        if loadedImage != nil {
            return "产品图片"
        }
        return imageURL == nil ? "无产品图片" : "产品图片"
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.quaternarySystemFill))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("产品图片加载失败")
        .accessibilityHint("连按两次以重试")
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.quaternarySystemFill))
    }

    @MainActor
    private func loadImageIfNeeded() async {
        guard let imageURL else {
            loadedImage = nil
            loadFailed = false
            isLoading = false
            return
        }

        isLoading = true
        loadFailed = false
        let token = reloadToken

        do {
            let data = try await ProductImageLoader.shared.loadImageData(
                from: imageURL,
                reloadToken: token
            )
            guard !Task.isCancelled, token == reloadToken else { return }
            if let image = NSImage(data: data) {
                loadedImage = image
                loadFailed = false
            } else {
                loadedImage = nil
                loadFailed = true
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, token == reloadToken else { return }
            loadedImage = nil
            loadFailed = true
        }

        isLoading = false
    }
}

#Preview {
    ProductImageView(
        imageURL: URL(string: "https://cdn.shopify.com/s/files/1/0887/9364/5331/files/svybxx1779861145029.jpg?v=1780033180")
    )
    .padding()
}
