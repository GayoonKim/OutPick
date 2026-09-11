import Foundation
import Testing
@testable import OutPick

struct ChatMediaSelectionChunkerTests {
    @Test func chunksReindexEveryMessageAndRespectCountLimit() {
        let images = (0..<31).map { makeImage(index: $0, bytes: 1) }

        let chunks = ChatMediaSelectionChunker.chunks(images)

        #expect(chunks.map(\.count) == [30, 1])
        #expect(chunks[0].map(\.index) == Array(0..<30))
        #expect(chunks[1].map(\.index) == [0])
    }

    @Test func chunksRespectAggregateByteLimit() {
        let eightyMiB = 160_000_000
        let chunks = ChatMediaSelectionChunker.chunks([
            makeImage(index: 0, bytes: eightyMiB),
            makeImage(index: 1, bytes: eightyMiB)
        ])

        #expect(chunks.map(\.count) == [1, 1])
    }

    @Test func decimalBoundaryAllowsExactly300MBAndSplitsNextImage() {
        let chunks = ChatMediaSelectionChunker.chunks([
            makeImage(index: 0, bytes: 150_000_000),
            makeImage(index: 1, bytes: 150_000_000),
            makeImage(index: 2, bytes: 1)
        ])
        #expect(chunks.map(\.count) == [2, 1])
        #expect(ChatPhotoSizePolicy.acceptsFile(bytes: 300_000_000))
        #expect(!ChatPhotoSizePolicy.acceptsFile(bytes: 300_000_001))
        #expect(!ChatPhotoSizePolicy.acceptsFile(bytes: 0))
    }

    @Test(arguments: [
        (count: 60, expectedChunkCounts: [30, 30]),
        (count: 70, expectedChunkCounts: [30, 30, 10])
    ])
    func largeSelectionsKeepEveryImageInOrderedChunks(
        count: Int,
        expectedChunkCounts: [Int]
    ) {
        let images = (0..<count).map { makeImage(index: $0, bytes: 1) }

        let chunks = ChatMediaSelectionChunker.chunks(images)

        #expect(chunks.map(\.count) == expectedChunkCounts)
        #expect(chunks.flatMap { $0 }.count == count)
        #expect(chunks.allSatisfy { chunk in
            chunk.map(\.index) == Array(0..<chunk.count)
        })
    }

    private func makeImage(index: Int, bytes: Int) -> ProcessedImage {
        ProcessedImage(
            index: index,
            originalFileURL: URL(fileURLWithPath: "/tmp/\(index).jpg"),
            thumbData: Data(),
            originalWidth: 10,
            originalHeight: 10,
            bytesOriginal: bytes,
            sha256: String(repeating: "a", count: 64)
        )
    }
}
