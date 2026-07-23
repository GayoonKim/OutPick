import Foundation
import Testing
import UIKit
@testable import OutPick

struct LookbookRemotePreviewImageLoaderTests {
    @Test func concurrentLoadsForSameRequestShareOneFetch() async throws {
        let spy = RemotePreviewFetchSpy()
        let loader = LookbookRemotePreviewImageLoader { request, _ in
            try await spy.fetch(request)
        }
        let request = makeRequest(suffix: UUID().uuidString)

        async let first = loader.loadImage(request: request, maxBytes: 1_000_000)
        async let second = loader.loadImage(request: request, maxBytes: 1_000_000)
        let images = try await [first, second]

        #expect(images.count == 2)
        #expect(await spy.fetchCount == 1)
    }

    @Test func prefetchRemovesDuplicateRequestsAndHonorsConcurrency() async {
        let spy = RemotePreviewFetchSpy()
        let loader = LookbookRemotePreviewImageLoader { request, _ in
            try await spy.fetch(request)
        }
        let first = makeRequest(suffix: UUID().uuidString)
        let second = makeRequest(suffix: UUID().uuidString)

        await loader.prefetch(
            requests: [first, first, second, second],
            maxBytes: 1_000_000,
            concurrency: 2
        )

        #expect(await spy.fetchCount == 2)
        #expect(await spy.maximumActiveFetchCount <= 2)
    }

    private func makeRequest(
        suffix: String
    ) -> LookbookRemotePreviewImageRequest {
        LookbookRemotePreviewImageRequest(
            remoteURL: URL(string: "https://example.com/\(suffix).png")!,
            sourcePageURL: URL(string: "https://example.com/lookbook")
        )
    }
}

private actor RemotePreviewFetchSpy {
    private(set) var fetchCount = 0
    private(set) var maximumActiveFetchCount = 0
    private var activeFetchCount = 0

    func fetch(
        _ request: LookbookRemotePreviewImageRequest
    ) async throws -> Data {
        _ = request
        fetchCount += 1
        activeFetchCount += 1
        maximumActiveFetchCount = max(
            maximumActiveFetchCount,
            activeFetchCount
        )
        try await Task.sleep(nanoseconds: 20_000_000)
        activeFetchCount -= 1

        return Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC" +
                "AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
        )!
    }
}
