import SwiftUI

struct ProductImageView: View {
    let imageURL: URL?

    @State private var reloadToken = 0

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURLWithReloadToken(imageURL)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        failurePlaceholder
                    @unknown default:
                        placeholder
                    }
                }
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
        .accessibilityLabel(imageURL == nil ? "无产品图片" : "产品图片")
    }

    private var failurePlaceholder: some View {
        VStack(spacing: 2) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("重试") {
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

    private func imageURLWithReloadToken(_ baseURL: URL) -> URL {
        guard reloadToken > 0 else { return baseURL }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "reload", value: "\(reloadToken)"))
        components?.queryItems = queryItems
        return components?.url ?? baseURL
    }
}

#Preview {
    ProductImageView(
        imageURL: URL(string: "https://cdn.shopify.com/s/files/1/0887/9364/5331/files/svybxx1779861145029.jpg?v=1780033180")
    )
    .padding()
}
