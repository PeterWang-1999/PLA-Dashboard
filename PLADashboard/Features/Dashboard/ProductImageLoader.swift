import Foundation
import ImageIO

/// CGImage 只读；跨 actor 传递后不修改其像素或提供器。
final class ProductThumbnail: NSObject, @unchecked Sendable {
    let image: CGImage
    var memoryCost: Int { image.bytesPerRow * image.height }
    init(image: CGImage) { self.image = image }
}

actor ProductImageLoader {
    static let shared = ProductImageLoader()
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private struct Key: Hashable {
        let url: URL
        let pixels: Int
        let reloadToken: Int
        var cacheKey: NSString { "\(url.absoluteString)|p\(pixels)" as NSString }
    }
    private struct Flight {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<ProductThumbnail, Error>]
    }

    private let fetch: Fetch
    private let memoryCache = NSCache<NSString, ProductThumbnail>()
    private let fetchLimiter: ImageFetchLimiter
    private var flights: [Key: Flight] = [:]
    private var cacheWriters: [NSString: UUID] = [:]
    var activeSubscriberCount: Int { flights.values.reduce(0) { $0 + $1.waiters.count } }

    init(fetch: Fetch? = nil, maxConcurrent: Int = 3, cacheByteLimit: Int = 32 * 1_024 * 1_024) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 20
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 3
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpCookieStorage = HTTPCookieStorage.shared
        configuration.httpShouldSetCookies = true
        let session = URLSession(configuration: configuration)
        self.fetch = fetch ?? { try await session.data(for: $0) }
        fetchLimiter = ImageFetchLimiter(maxConcurrent: maxConcurrent)
        memoryCache.countLimit = 300
        memoryCache.totalCostLimit = max(1, cacheByteLimit)
    }

    func loadThumbnail(from url: URL, maxPixelSize: Int, reloadToken: Int = 0) async throws -> ProductThumbnail {
        try Task.checkCancellation()
        let key = Key(url: url, pixels: max(1, min(maxPixelSize, 4_096)), reloadToken: reloadToken)
        if reloadToken == 0, let cached = memoryCache.object(forKey: key.cacheKey) { return cached }
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if var flight = flights[key] {
                    flight.waiters[waiterID] = continuation
                    flights[key] = flight
                    return
                }
                let flightID = UUID()
                cacheWriters[key.cacheKey] = flightID
                let task = Task {
                    do {
                        let thumbnail = try await fetchLimiter.withPermit {
                            let data = try await self.fetchImageData(from: url, reloadToken: reloadToken)
                            return try Self.downsample(data: data, maxPixelSize: key.pixels)
                        }
                        try Task.checkCancellation()
                        complete(key, flightID: flightID, result: .success(thumbnail))
                    } catch {
                        complete(key, flightID: flightID, result: .failure(error))
                    }
                }
                flights[key] = Flight(id: flightID, task: task, waiters: [waiterID: continuation])
            }
        } onCancel: {
            Task { await self.cancel(key, waiterID: waiterID) }
        }
    }

    private func cancel(_ key: Key, waiterID: UUID) {
        guard var flight = flights[key], let waiter = flight.waiters.removeValue(forKey: waiterID) else { return }
        waiter.resume(throwing: CancellationError())
        if flight.waiters.isEmpty {
            flights.removeValue(forKey: key)
            if cacheWriters[key.cacheKey] == flight.id { cacheWriters.removeValue(forKey: key.cacheKey) }
            flight.task.cancel()
        } else {
            flights[key] = flight
        }
    }

    private func complete(_ key: Key, flightID: UUID, result: Result<ProductThumbnail, Error>) {
        guard let flight = flights[key], flight.id == flightID else { return }
        flights.removeValue(forKey: key)
        if cacheWriters[key.cacheKey] == flightID {
            cacheWriters.removeValue(forKey: key.cacheKey)
            if case .success(let thumbnail) = result {
                // 重试更新正常缓存，不为每个重试令牌额外保留一份图像。
                memoryCache.setObject(thumbnail, forKey: key.cacheKey, cost: thumbnail.memoryCost)
            }
        }
        for waiter in flight.waiters.values { waiter.resume(with: result) }
    }

    nonisolated static func downsample(data: Data, maxPixelSize: Int) throws -> ProductThumbnail {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, min(maxPixelSize, 4_096)),
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw URLError(.cannotDecodeContentData) }
        try Task.checkCancellation()
        return ProductThumbnail(image: image)
    }

    private func fetchImageData(from url: URL, reloadToken: Int) async throws -> Data {
        var lastError: Error = URLError(.badServerResponse)
        for attempt in 0..<3 {
            try Task.checkCancellation()
            if attempt > 0 { try await Task.sleep(for: .milliseconds(250 * attempt)) }
            var request = URLRequest(url: url)
            request.cachePolicy = reloadToken > 0 || attempt > 0 ? .reloadIgnoringLocalCacheData : .returnCacheDataElseLoad
            if RightInTheBoxImageCDN.shouldApplyBrowserHeaders(for: url.host) {
                request.setValue(RightInTheBoxImageCDN.referer, forHTTPHeaderField: "Referer")
                request.setValue(RightInTheBoxImageCDN.safariUserAgent, forHTTPHeaderField: "User-Agent")
                request.setValue("image/jpeg,image/png,image/*;q=0.8", forHTTPHeaderField: "Accept")
            }
            do {
                let (data, response) = try await fetch(request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                guard !data.isEmpty else { throw URLError(.zeroByteResource) }
                return data
            } catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError {
                    throw CancellationError()
                }
                lastError = error
            }
        }
        throw lastError
    }
}

actor ImageFetchLimiter {
    private var available: Int
    private var waiters: [(UUID, CheckedContinuation<Void, Error>)] = []
    init(maxConcurrent: Int) { available = max(1, maxConcurrent) }

    func withPermit<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try await acquire()
        defer { release() }
        try Task.checkCancellation()
        return try await operation()
    }

    private func acquire() async throws {
        try Task.checkCancellation()
        if available > 0 { available -= 1; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
                else { waiters.append((id, continuation)) }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else { return }
        waiters.remove(at: index).1.resume(throwing: CancellationError())
    }
    private func release() {
        if !waiters.isEmpty { waiters.removeFirst().1.resume() }
        else { available += 1 }
    }
}
