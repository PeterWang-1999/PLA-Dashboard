import SwiftUI

struct ProductImageView: View {
    let imageURL: URL?

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .controlSize(.small)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
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
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.quaternarySystemFill))
    }
}

#Preview {
    ProductImageView(
        imageURL: URL(string: "https://cdn.shopify.com/s/files/1/0887/9364/5331/files/svybxx1779861145029.jpg?v=1780033180")
    )
    .padding()
}
