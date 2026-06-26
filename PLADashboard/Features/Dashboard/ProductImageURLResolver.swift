import Foundation

/// 将 Merchant「图片链接」原始字符串规范为可请求的绝对 HTTPS URL。
enum ProductImageURLResolver {
    static func resolve(_ raw: String?) -> URL? {
        guard var trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("//") {
            trimmed = "https:" + trimmed
        } else if !trimmed.contains("://") {
            if trimmed.hasPrefix("/") {
                return nil
            }
            if trimmed.contains(".") {
                trimmed = "https://" + trimmed
            } else {
                return nil
            }
        }

        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return nil
        }
        guard scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }
}
