import XCTest
import ImageIO
@testable import PLADashboard

@MainActor
final class ProductImageLoaderTests: XCTestCase {
    private let url = URL(string: "https://example.com/product.jpg")!

    private static func jpeg(width: Int = 4_000, height: Int = 3_000, orientation: Int = 1) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func waitForSubscribers(_ count: Int, loader: ProductImageLoader) async throws {
        let deadline = Date().addingTimeInterval(3)
        while await loader.activeSubscriberCount < count {
            guard Date() < deadline else { throw URLError(.timedOut) }
            await Task.yield()
        }
    }

    func testDownsampleUsesRequestedPixelsAndDecodedByteCost() async throws {
        let data = try Self.jpeg()
        let probe = ImageFetchProbe(data: data)
        let loader = ProductImageLoader(fetch: { try await probe.fetch($0) })
        for pixels in [80, 144, 560] {
            let thumbnail = try await loader.loadThumbnail(from: url, maxPixelSize: pixels)
            XCTAssertEqual(max(thumbnail.image.width, thumbnail.image.height), pixels)
            XCTAssertEqual(thumbnail.memoryCost, thumbnail.image.bytesPerRow * thumbnail.image.height)
            XCTAssertLessThan(thumbnail.memoryCost, 4_000 * 3_000 * 4)
        }
        let usedMainThread = await probe.usedMainThread
        XCTAssertFalse(usedMainThread)
    }

    func testThumbnailAppliesEXIFOrientation() async throws {
        let probe = ImageFetchProbe(data: try Self.jpeg(width: 800, height: 400, orientation: 6))
        let loader = ProductImageLoader(fetch: { try await probe.fetch($0) })
        let thumbnail = try await loader.loadThumbnail(from: url, maxPixelSize: 80)
        XCTAssertEqual(thumbnail.image.width, 40)
        XCTAssertEqual(thumbnail.image.height, 80)
    }

    func testCacheReusesDecodedImageAndRetryReplacesNormalCache() async throws {
        let probe = ImageFetchProbe(data: try Self.jpeg(width: 800, height: 600))
        let loader = ProductImageLoader(fetch: { try await probe.fetch($0) })
        let original = try await loader.loadThumbnail(from: url, maxPixelSize: 80)
        let cached = try await loader.loadThumbnail(from: url, maxPixelSize: 80)
        XCTAssertTrue(original === cached)
        let retry = try await loader.loadThumbnail(from: url, maxPixelSize: 80, reloadToken: 1)
        let updated = try await loader.loadThumbnail(from: url, maxPixelSize: 80)
        XCTAssertTrue(retry === updated)
        XCTAssertFalse(retry === original)
        let requests = await probe.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests.last?.cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testSameURLAndSizeShareRequestAndOneCancellationDoesNotCancelOther() async throws {
        let probe = ImageFetchProbe(data: try Self.jpeg(width: 800, height: 600), holding: true)
        let loader = ProductImageLoader(fetch: { try await probe.fetch($0) })
        let first = Task { try await loader.loadThumbnail(from: url, maxPixelSize: 80) }
        let second = Task { try await loader.loadThumbnail(from: url, maxPixelSize: 80) }
        try await waitForSubscribers(2, loader: loader)
        first.cancel()
        do { _ = try await first.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        await probe.release()
        let image = try await second.value
        XCTAssertEqual(image.image.width, 80)
        let requestCount = await probe.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testCancelledQueuedImageDoesNotFetchOrConsumePermit() async throws {
        let started = expectation(description: "first network request started")
        let probe = ImageFetchProbe(data: try Self.jpeg(width: 800, height: 600), holding: true, started: started)
        let loader = ProductImageLoader(fetch: { try await probe.fetch($0) }, maxConcurrent: 1)
        let first = Task { try await loader.loadThumbnail(from: url, maxPixelSize: 80) }
        await fulfillment(of: [started], timeout: 3)
        let otherURL = URL(string: "https://example.com/other.jpg")!
        let queued = Task { try await loader.loadThumbnail(from: otherURL, maxPixelSize: 80) }
        try await waitForSubscribers(2, loader: loader)
        queued.cancel()
        do { _ = try await queued.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let beforeRelease = await probe.requests.count
        XCTAssertEqual(beforeRelease, 1)
        await probe.release()
        _ = try await first.value
        _ = try await loader.loadThumbnail(from: otherURL, maxPixelSize: 80)
        let count = await probe.requests.count
        XCTAssertEqual(count, 2)
    }

    func testCorruptImageFailsWithoutDecodedCacheEntry() async throws {
        let probe = ImageFetchProbe(data: Data("invalid image".utf8))
        let loader = ProductImageLoader(fetch: { try await probe.fetch($0) })
        for _ in 0..<2 {
            do { _ = try await loader.loadThumbnail(from: url, maxPixelSize: 80); XCTFail("Expected decode error") }
            catch { XCTAssertEqual((error as? URLError)?.code, .cannotDecodeContentData) }
        }
        let count = await probe.requests.count
        XCTAssertEqual(count, 2)
    }
}

private actor ImageFetchProbe {
    let data: Data
    private var holding: Bool
    private let started: XCTestExpectation?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var requests: [URLRequest] = []
    private(set) var usedMainThread = false
    init(data: Data, holding: Bool = false, started: XCTestExpectation? = nil) {
        self.data = data; self.holding = holding; self.started = started
    }
    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        usedMainThread = usedMainThread || Thread.isMainThread
        if requests.count == 1 { started?.fulfill() }
        if holding { await withCheckedContinuation { waiters.append($0) } }
        try Task.checkCancellation()
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
    func release() {
        holding = false
        for waiter in waiters { waiter.resume() }
        waiters.removeAll()
    }
}
