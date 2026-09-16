import Foundation
import Testing
import UIKit
@testable import OutPick

struct LookbookHTTPImageCacheTests {
    @Test func freshEntrySkipsSecondNetworkRequest() async throws {
        let body = try Self.imageData()
        let spy = ResponseSpy([.init(status: 200, headers: ["Cache-Control": "max-age=3600", "ETag": "v1"], body: body)])
        let cache = makeCache(spy: spy)
        let request = Self.request()

        _ = try await cache.updatedImage(for: request)
        _ = try await cache.updatedImage(for: request)

        #expect(await spy.count == 1)
        #expect(await cache.cachedImage(for: request)?.isFresh == true)
        await cache.flushPendingWrites()
    }

    @Test func expiredEntryUsesValidatorAnd304RetainsBody() async throws {
        let body = try Self.imageData()
        let spy = ResponseSpy([
            .init(status: 200, headers: ["Cache-Control": "max-age=0", "ETag": "v1"], body: body),
            .init(status: 304, headers: ["Cache-Control": "max-age=3600"], body: Data())
        ])
        let cache = makeCache(spy: spy)
        let request = Self.request()

        let first = try await cache.updatedImage(for: request)
        await cache.flushPendingWrites()
        #expect(await cache.cachedImage(for: request)?.isFresh == false)
        let second = try await cache.updatedImage(for: request)

        #expect(first.size == second.size)
        #expect(await spy.count == 2)
        #expect(await spy.lastIfNoneMatch == "v1")
        #expect(await cache.cachedImage(for: request)?.isFresh == true)
    }

    @Test func noCacheRequiresValidationBeforeReuseAndNoStoreDoesNotPersist() async throws {
        let body = try Self.imageData()
        let spy = ResponseSpy([
            .init(status: 200, headers: ["Cache-Control": "no-cache", "ETag": "v1"], body: body),
            .init(status: 304, headers: ["Cache-Control": "no-cache"], body: Data()),
            .init(status: 200, headers: ["Cache-Control": "no-store"], body: body)
        ])
        let cache = makeCache(spy: spy)
        let request = Self.request()

        _ = try await cache.updatedImage(for: request)
        await cache.flushPendingWrites()
        #expect(await cache.cachedImage(for: request)?.requiresValidation == true)
        _ = try await cache.updatedImage(for: request)
        #expect(await spy.count == 2)
        _ = try await cache.updatedImage(for: request)
        #expect(await cache.cachedImage(for: request) == nil)
    }

    @Test func permanent404RemovesStaleImage() async throws {
        let body = try Self.imageData()
        let spy = ResponseSpy([
            .init(status: 200, headers: ["Cache-Control": "max-age=0"], body: body),
            .init(status: 404, headers: [:], body: Data())
        ])
        let cache = makeCache(spy: spy)
        let request = Self.request()
        _ = try await cache.updatedImage(for: request)
        await cache.flushPendingWrites()

        do {
            _ = try await cache.updatedImage(for: request)
            Issue.record("404 응답이 성공했습니다.")
        } catch {
            guard case LookbookHTTPImageError.permanentStatus(404) = error else {
                Issue.record("예상하지 못한 오류: \(error)")
                return
            }
        }
        #expect(await cache.cachedImage(for: request) == nil)
    }

    @Test func concurrentExpiredConsumersShareOneValidation() async throws {
        let body = try Self.imageData()
        let spy = ResponseSpy([
            .init(status: 200, headers: ["Cache-Control": "max-age=0", "ETag": "v1"], body: body),
            .init(status: 304, headers: ["Cache-Control": "max-age=3600"], body: Data())
        ], delayAfterFirst: true)
        let cache = makeCache(spy: spy)
        let request = Self.request()
        _ = try await cache.updatedImage(for: request)
        await cache.flushPendingWrites()

        async let first = cache.updatedImage(for: request)
        async let second = cache.updatedImage(for: request)
        _ = try await (first, second)
        #expect(await spy.count == 2)
    }

    @Test func transientFailureKeepsStaleAndBackoffPreventsImmediateRepeat() async throws {
        let body = try Self.imageData()
        let spy = ResponseSpy([
            .init(status: 200, headers: ["Cache-Control": "max-age=0"], body: body),
            .init(status: 503, headers: [:], body: Data())
        ])
        let cache = makeCache(spy: spy)
        let request = Self.request()
        _ = try await cache.updatedImage(for: request)
        await cache.flushPendingWrites()

        _ = try await cache.updatedImage(for: request)
        _ = try await cache.updatedImage(for: request)
        #expect(await spy.count == 2)
        #expect(await cache.cachedImage(for: request) != nil)
    }

    @Test func metadataAndBodySurviveCacheActorRestart() async throws {
        let body = try Self.imageData()
        let spy = ResponseSpy([
            .init(status: 200, headers: ["Cache-Control": "max-age=3600"], body: body)
        ])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LookbookHTTPTests-\(UUID())")
        let request = Self.request()
        let first = makeCache(spy: spy, directory: directory)
        _ = try await first.updatedImage(for: request)
        await first.flushPendingWrites()

        let second = makeCache(spy: spy, directory: directory)
        #expect(await second.cachedImage(for: request)?.isFresh == true)
        _ = try await second.updatedImage(for: request)
        #expect(await spy.count == 1)
    }

    @Test func diskBodyWaitsForDecodeBudgetBeforeReadingAndHandlesEviction() async throws {
        let body = try Self.imageData()
        let spy = ResponseSpy([.init(status: 200, headers: ["Cache-Control": "max-age=3600"], body: body)])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("LookbookHTTPTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = Self.request()
        let writer = makeCache(spy: spy, directory: directory)
        _ = try await writer.updatedImage(for: request)
        await writer.flushPendingWrites()
        let metadataData = try Data(contentsOf: directory.appendingPathComponent(request.key).appendingPathExtension("json"))
        let metadata = try #require(JSONSerialization.jsonObject(with: metadataData) as? [String: Any])
        let bodyKey = try #require(metadata["bodyKey"] as? String)

        let resources = ImagePipelineResources()
        let reader = LookbookHTTPImageCache(resources: resources, directory: directory,
                                            fetch: { request, maxBytes in try await spy.fetch(request, maxBytes: maxBytes) })
        let held = try await resources.decodeBytes.acquire(resources.limits.decodeBytes)
        let load = Task { await reader.cachedImage(for: request) }
        for _ in 0..<300 {
            if await resources.decodeBytes.snapshot().waiting > 0 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let waiting = await resources.decodeBytes.snapshot().waiting
        #expect(waiting == 1)
        // 용량을 기다리는 동안 캐시가 제거되어도 본문을 미리 보유하면 안 된다.
        let disk = ImageCacheDiskStore(folderName: "LookbookHTTPImageBodies", resources: resources)
        await disk.remove(forKey: bodyKey)
        await held.release()
        #expect(await load.value == nil)
        #expect(await resources.decodeBytes.snapshot().used == 0)
        #expect(await spy.count == 1)
    }

    @Test func validatorFreeResponseComparesBodyAndRefreshesExpiry() async throws {
        let body = try Self.imageData()
        let spy = ResponseSpy([
            .init(status: 200, headers: ["Cache-Control": "max-age=0"], body: body),
            .init(status: 200, headers: ["Cache-Control": "max-age=3600"], body: body)
        ])
        let cache = makeCache(spy: spy)
        let request = Self.request()
        _ = try await cache.updatedImage(for: request)
        await cache.flushPendingWrites()
        _ = try await cache.updatedImage(for: request)

        #expect(await spy.count == 2)
        #expect(await spy.lastIfNoneMatch == nil)
        #expect(await cache.cachedImage(for: request)?.isFresh == true)
    }

    @Test func refererAndByteLimitProduceDifferentCacheKeys() {
        let url = URL(string: "https://example.com/image.png")!
        let first = LookbookHTTPImageRequest(remoteURL: url, sourcePageURL: URL(string: "https://example.com/a"), maxBytes: 500_000)
        let second = LookbookHTTPImageRequest(remoteURL: url, sourcePageURL: URL(string: "https://example.com/b"), maxBytes: 500_000)
        let third = LookbookHTTPImageRequest(remoteURL: url, sourcePageURL: first.sourcePageURL, maxBytes: 1_000_000)
        #expect(first.key != second.key)
        #expect(first.key != third.key)
    }

    @Test func assetPrefetchFollowsTheSameCandidateOrderAsDisplay() async {
        let fake = AssetPrefetchFake()
        let request = LookbookAssetImageRequest(
            primaryPath: " thumb ", secondaryPath: "detail",
            remoteURL: URL(string: "https://example.com/image.png"),
            sourcePageURL: nil, maxBytes: 1_000_000
        )
        await fake.prefetchAssets(items: [request], concurrency: 1, storePolicy: .memoryOnly)
        #expect(request.storagePaths == ["thumb", "detail"])
        #expect(await fake.requestedPaths == ["thumb", "detail"])
        #expect(await fake.remoteRequests == 1)
    }

    @Test func changed200ReplacesThePreparedImage() async throws {
        let firstBody = try Self.imageData(color: .systemPink)
        let secondBody = try Self.imageData(color: .systemBlue)
        let spy = ResponseSpy([
            .init(status: 200, headers: ["Cache-Control": "max-age=0", "ETag": "v1"], body: firstBody),
            .init(status: 200, headers: ["Cache-Control": "max-age=3600", "ETag": "v2"], body: secondBody)
        ])
        let cache = makeCache(spy: spy)
        let request = Self.request()
        let first = try await cache.updatedImage(for: request)
        await cache.flushPendingWrites()
        let second = try await cache.updatedImage(for: request)
        #expect(first.pngData() != second.pngData())
        #expect(await cache.cachedImage(for: request)?.isFresh == true)
    }

    @Test func serverAgeReducesRemainingMaxAge() async throws {
        let body = try Self.imageData()
        let spy = ResponseSpy([
            .init(status: 200, headers: ["Cache-Control": "max-age=3600", "Age": "3600"], body: body)
        ])
        let cache = makeCache(spy: spy)
        let request = Self.request()
        _ = try await cache.updatedImage(for: request)
        #expect(await cache.cachedImage(for: request)?.isFresh == false)
        await cache.flushPendingWrites()
    }

    private func makeCache(spy: ResponseSpy, directory: URL? = nil) -> LookbookHTTPImageCache {
        LookbookHTTPImageCache(
            directory: directory ?? FileManager.default.temporaryDirectory.appendingPathComponent("LookbookHTTPTests-\(UUID())"),
            fetch: { request, maxBytes in try await spy.fetch(request, maxBytes: maxBytes) }
        )
    }

    private static func request() -> LookbookHTTPImageRequest {
        LookbookHTTPImageRequest(
            remoteURL: URL(string: "https://example.com/\(UUID()).png")!,
            sourcePageURL: URL(string: "https://example.com/lookbook"),
            maxBytes: 1_000_000
        )
    }

    private static func imageData(color: UIColor = .systemPink) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 3, height: 3), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3, height: 3))
        }
        return try #require(image.pngData())
    }
}

private actor ResponseSpy {
    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    private var responses: [Response]
    private let delayAfterFirst: Bool
    private(set) var count = 0
    private(set) var lastIfNoneMatch: String?

    init(_ responses: [Response], delayAfterFirst: Bool = false) {
        self.responses = responses
        self.delayAfterFirst = delayAfterFirst
    }

    func fetch(_ request: URLRequest, maxBytes: Int) async throws -> (Data, HTTPURLResponse) {
        count += 1
        if delayAfterFirst && count == 2 { try await Task.sleep(nanoseconds: 50_000_000) }
        lastIfNoneMatch = request.value(forHTTPHeaderField: "If-None-Match")
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let next = responses.removeFirst()
        guard let response = HTTPURLResponse(
            url: request.url!, statusCode: next.status, httpVersion: "HTTP/1.1", headerFields: next.headers
        ) else { throw URLError(.badServerResponse) }
        return (next.body, response)
    }
}

private actor AssetPrefetchFake: BrandImageCacheProtocol {
    private(set) var requestedPaths: [String] = []
    private(set) var remoteRequests = 0

    func loadImage(path: String, maxBytes: Int) async throws -> UIImage {
        requestedPaths.append(path)
        throw URLError(.fileDoesNotExist)
    }

    func cachedRemoteImage(request: LookbookHTTPImageRequest) async -> LookbookHTTPImageCache.CachedImage? { nil }

    func updatedRemoteImage(request: LookbookHTTPImageRequest) async throws -> UIImage {
        remoteRequests += 1
        return UIImage()
    }

    func retryRemoteImage(request: LookbookHTTPImageRequest) async throws -> UIImage {
        try await updatedRemoteImage(request: request)
    }

    func storeImageData(_ data: Data, path: String) async throws {}
    func removeImage(path: String) async {}
    func prefetch(items: [(path: String, maxBytes: Int)], concurrency: Int, storePolicy: ImageCacheStorePolicy) async {}
}
