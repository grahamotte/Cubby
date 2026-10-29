import AppKit
import XCTest
@testable import CubbyCore

@MainActor
final class ThumbnailCacheTests: XCTestCase {
    private final class Request {
        let url: URL
        let completion: (NSImage?, Bool) -> Void
        var cancelled = false

        init(url: URL, completion: @escaping (NSImage?, Bool) -> Void) {
            self.url = url
            self.completion = completion
        }
    }

    private var requests: [Request] = []
    private let image = NSImage(size: NSSize(width: 8, height: 8))

    private func makeCache() -> ThumbnailCache {
        ThumbnailCache(generator: ThumbnailGenerator { url, _, _, _, completion in
            let request = Request(url: url, completion: completion)
            self.requests.append(request)
            return request
        } cancel: { request in
            (request as? Request)?.cancelled = true
        })
    }

    private let photo = item("photo.jpg", size: 10)

    func testDeliversAndCachesThumbnail() {
        let cache = makeCache()
        let delivered = expectation(description: "delivered")
        cache.thumbnail(for: photo, size: 64, scale: 2) { thumbnail in
            XCTAssertTrue(thumbnail.rounded)
            delivered.fulfill()
        }
        requests[0].completion(image, true)
        wait(for: [delivered], timeout: 1)
        XCTAssertNotNil(cache.cached(for: photo, size: 64))
        var immediate: Thumbnail?
        cache.thumbnail(for: photo, size: 64, scale: 2) { immediate = $0 }
        XCTAssertNotNil(immediate)
        XCTAssertEqual(requests.count, 1)
    }

    func testConcurrentRequestsShareOneGeneration() {
        let cache = makeCache()
        let delivered = expectation(description: "delivered")
        delivered.expectedFulfillmentCount = 2
        cache.thumbnail(for: photo, size: 64, scale: 2) { _ in delivered.fulfill() }
        cache.thumbnail(for: photo, size: 64, scale: 2) { _ in delivered.fulfill() }
        XCTAssertEqual(requests.count, 1)
        requests[0].completion(image, false)
        wait(for: [delivered], timeout: 1)
    }

    func testCancelStopsRequestAndDropsCompletion() {
        let cache = makeCache()
        cache.thumbnail(for: photo, size: 64, scale: 2) { _ in XCTFail("cancelled completion called") }
        cache.cancel(for: photo, size: 64)
        XCTAssertTrue(requests[0].cancelled)
        requests[0].completion(nil, false)
        drainMainQueue()
        XCTAssertNil(cache.cached(for: photo, size: 64))
    }

    func testRequestAgainAfterCancelGetsThumbnailWhenCancelledCallbackArrivesFirst() {
        let cache = makeCache()
        cache.thumbnail(for: photo, size: 64, scale: 2) { _ in XCTFail("cancelled completion called") }
        cache.cancel(for: photo, size: 64)
        let delivered = expectation(description: "delivered")
        cache.thumbnail(for: photo, size: 64, scale: 2) { _ in delivered.fulfill() }
        XCTAssertEqual(requests.count, 2)
        requests[0].completion(nil, false)
        requests[1].completion(image, true)
        wait(for: [delivered], timeout: 1)
        XCTAssertNotNil(cache.cached(for: photo, size: 64))
    }

    func testFailedGenerationAllowsRetry() {
        let cache = makeCache()
        cache.thumbnail(for: photo, size: 64, scale: 2) { _ in XCTFail("no image to deliver") }
        requests[0].completion(nil, false)
        drainMainQueue()
        cache.thumbnail(for: photo, size: 64, scale: 2) { _ in }
        XCTAssertEqual(requests.count, 2)
    }

    func testSkipsItemsWithoutThumbnails() {
        let cache = makeCache()
        cache.thumbnail(for: item("folder", directory: true), size: 64, scale: 2) { _ in }
        cache.thumbnail(for: item("empty.txt"), size: 64, scale: 2) { _ in }
        XCTAssertTrue(requests.isEmpty)
    }

    func testRequestSizesAreBucketed() {
        XCTAssertEqual(ThumbnailCache.requestSize(20), 32)
        XCTAssertEqual(ThumbnailCache.requestSize(64), 64)
        XCTAssertEqual(ThumbnailCache.requestSize(80), 128)
    }

    private func drainMainQueue() {
        let drained = expectation(description: "drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
    }
}
