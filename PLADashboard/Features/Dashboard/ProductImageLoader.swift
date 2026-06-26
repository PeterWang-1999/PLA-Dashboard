import Foundation

actor ProductImageLoader {
    static let shared = ProductImageLoader()

    private let session: URLSession
    private let memoryCache = NSCache<NSURL, NSData>()

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: configuration)
        memoryCache.countLimit = 300
    }

    func loadImageData(from url: URL, reloadToken: Int = 0) async throws -> Data {
        let requestURL = urlWithReloadToken(url, reloadToken: reloadToken)
        let cacheKey = requestURL as NSURL

        if reloadToken == 0, let cached = memoryCache.object(forKey: cacheKey) {
            return cached as Data
        }

        var request = URLRequest(url: requestURL)
        request.cachePolicy = reloadToken > 0 ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard !data.isEmpty else {
            throw URLError(.zeroByteResource)
        }

        memoryCache.setObject(data as NSData, forKey: cacheKey)
        return data
    }

    private func urlWithReloadToken(_ baseURL: URL, reloadToken: Int) -> URL {
        guard reloadToken > 0 else { return baseURL }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        var queryItems = components?.queryItems ?? []
        queryItems.append(URLQueryItem(name: "reload", value: "\(reloadToken)"))
        components?.queryItems = queryItems
        return components?.url ?? baseURL
    }
}
