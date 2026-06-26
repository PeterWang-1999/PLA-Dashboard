import Foundation

/// 将 Merchant「图片链接」原始字符串规范为可请求的图片 URL。
enum ProductImageURLResolver {
    private static let rightInTheBoxHostSuffix = "rightinthebox.com"

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

        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }

        if isRightInTheBoxImageHost(components.host) {
            components = normalizeRightInTheBoxURL(components)
        }

        return components.url
    }

    private static func isRightInTheBoxImageHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == RightInTheBoxImageCDN.litbimgHost
            || host == RightInTheBoxImageCDN.litbCGISHost
            || host.hasSuffix(".\(rightInTheBoxHostSuffix)")
    }

    /// litbimg CDN 对任意 query（含 `?f=0`、重试时的 `?reload=`）返回 403；去掉全部 query 后浏览器可正常访问。
    private static func normalizeRightInTheBoxURL(_ components: URLComponents) -> URLComponents {
        var normalized = components
        normalized.queryItems = nil
        normalized.percentEncodedQuery = nil
        return normalized
    }
}

enum RightInTheBoxImageCDN {
    static let litbimgHost = "litbimg.rightinthebox.com"
    static let litbCGISHost = "litb-cgis.rightinthebox.com"
    static let referer = "https://www.lightinthebox.com/"
    static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func shouldApplyBrowserHeaders(for host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == litbimgHost || host == litbCGISHost || host.hasSuffix(".rightinthebox.com")
    }
}
