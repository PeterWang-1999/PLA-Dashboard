import Foundation

actor ProductImageLoader {
    static let shared = ProductImageLoader()

    private let session: URLSession
    private let memoryCache = NSCache<NSString, NSData>()
    private let fetchLimiter = ImageFetchLimiter(maxConcurrent: 3)

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        session = URLSession(configuration: configuration)
        memoryCache.countLimit = 300
    }

    func loadImageData(from url: URL, reloadToken: Int = 0) async throws -> Data {
        let cacheKey = cacheKey(for: url, reloadToken: reloadToken)

        if reloadToken == 0, let cached = memoryCache.object(forKey: cacheKey) {
            return cached as Data
        }

        return try await fetchLimiter.withPermit {
            try await self.fetchImageData(from: url, reloadToken: reloadToken, cacheKey: cacheKey)
        }
    }

    private func fetchImageData(
        from url: URL,
        reloadToken: Int,
        cacheKey: NSString
    ) async throws -> Data {
        var lastError: Error = URLError(.badServerResponse)
        let bypassCache = reloadToken > 0

        for attempt in 0..<3 {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: UInt64(250_000_000 * attempt))
            }

            var request = URLRequest(url: url)
            request.cachePolicy = bypassCache || attempt > 0
                ? .reloadIgnoringLocalCacheData
                : .returnCacheDataElseLoad
            applyCDNHeaders(to: &request, for: url)

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard (200...299).contains(http.statusCode) else {
                    lastError = URLError(.badServerResponse)
                    if Self.isRetriableStatus(http.statusCode), attempt < 2 {
                        continue
                    }
                    throw lastError
                }
                guard !data.isEmpty else {
                    throw URLError(.zeroByteResource)
                }

                memoryCache.setObject(data as NSData, forKey: cacheKey)
                return data
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw error
            } catch {
                lastError = error
                if attempt < 2 {
                    continue
                }
                throw error
            }
        }

        throw lastError
    }

    private func applyCDNHeaders(to request: inout URLRequest, for url: URL) {
        guard RightInTheBoxImageCDN.shouldApplyBrowserHeaders(for: url.host) else { return }
        request.setValue(RightInTheBoxImageCDN.referer, forHTTPHeaderField: "Referer")
        request.setValue(RightInTheBoxImageCDN.safariUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/jpeg,image/png,image/*;q=0.8", forHTTPHeaderField: "Accept")
    }

    private func cacheKey(for url: URL, reloadToken: Int) -> NSString {
        if reloadToken == 0 {
            return url.absoluteString as NSString
        }
        return "\(url.absoluteString)|r\(reloadToken)" as NSString
    }

    private static func isRetriableStatus(_ statusCode: Int) -> Bool {
        switch statusCode {
        case 403, 408, 429, 500, 502, 503, 504:
            return true
        default:
            return false
        }
    }
}

private actor ImageFetchLimiter {
    private let maxConcurrent: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
        available = self.maxConcurrent
    }

    func withPermit<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if let waiter = waiters.first {
            waiters.removeFirst()
            waiter.resume()
        } else {
            available = min(available + 1, maxConcurrent)
        }
    }
}
