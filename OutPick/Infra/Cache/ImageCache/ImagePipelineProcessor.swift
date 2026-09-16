import Foundation
import UIKit

/// 바이트 예약·전송·디코딩을 연결한다. 각 단계의 permit은 그 단계에서만 소유한다.
final class ImagePipelineProcessor {
    typealias FileFetcher = @Sendable (String, Int, URL) async throws -> Void
    let resources: ImagePipelineResources
    private let fetcher: ImageCachePipeline.Fetcher
    private let fileFetcher: FileFetcher?
    private let decoder: @Sendable (Data) -> UIImage?
    private let fileDecoder: @Sendable (URL) -> UIImage?

    init(resources: ImagePipelineResources, fetcher: @escaping ImageCachePipeline.Fetcher, fileFetcher: FileFetcher?, decoder: @escaping @Sendable (Data) -> UIImage?, fileDecoder: @escaping @Sendable (URL) -> UIImage?) {
        self.resources = resources
        self.fetcher = fetcher
        self.fileFetcher = fileFetcher
        self.decoder = decoder
        self.fileDecoder = fileDecoder
    }

    func download(path: String, maxBytes: Int) async throws -> ImageLoadValue {
        guard maxBytes > 0 else { throw ImageCachePipelineError.imageTooLarge }
        let capacity = min(resources.limits.decodeBytes, resources.limits.writeBytes)
        if maxBytes > capacity { return try await downloadFile(path: path, maxBytes: maxBytes) }
        // 저장까지 입장을 예약하므로 이미 준비된 이미지가 저장 큐 입장을 기다리지 않는다.
        let writeLease = try await resources.writeBytes.acquire(maxBytes)
        let decodeLease: ImageStageGate.Lease
        do { decodeLease = try await resources.decodeBytes.acquire(maxBytes) }
        catch { await writeLease.release(); throw error }
        do {
            let data = try await resources.network.withPermit { [fetcher] in try await fetcher(path, maxBytes) }
            guard data.count <= maxBytes else { throw ImageCachePipelineError.imageTooLarge }
            ImageCacheMetrics.shared.mark("network.body.received", key: path, outcome: "data", bytes: data.count)
            await writeLease.reduce(to: max(1, data.count))
            await decodeLease.reduce(to: max(1, data.count))
            let image = try await prepare(.data(data))
            await decodeLease.release()
            return ImageLoadValue(image: image, payload: .data(data), release: { await writeLease.release() })
        } catch {
            await decodeLease.release()
            await writeLease.release()
            throw error
        }
    }

    private func downloadFile(path: String, maxBytes: Int) async throws -> ImageLoadValue {
        guard let fileFetcher else { throw ImageCachePipelineError.missingFileTransport }
        let lease = try await resources.files.acquire()
        do {
            let file = try ImageTemporaryFile()
            // 파일 다운로드의 쓰기도 I/O 예산에 포함한다. I/O 대기 중 network slot은 잡지 않는다.
            try await resources.io.withPermit(kind: .write) { [resources] in
                try await resources.network.withPermit { try await fileFetcher(path, maxBytes, file.url) }
            }
            let size = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= maxBytes else { throw ImageCachePipelineError.imageTooLarge }
            ImageCacheMetrics.shared.mark("network.body.received", key: path, outcome: "file", bytes: size)
            let image = try await prepare(.file(file))
            return ImageLoadValue(image: image, payload: .file(file), release: { await lease.release() })
        } catch { await lease.release(); throw error }
    }

    func cached(disk: ImageCacheDiskStore, key: String, revision: UInt64) async throws -> ImageLoadValue {
        guard let size = await disk.size(forKey: key, revision: revision) else {
            ImageCacheMetrics.shared.mark("cache", key: key, outcome: "miss")
            return ImageLoadValue(image: nil)
        }
        if size > resources.limits.decodeBytes {
            let lease = try await resources.files.acquire()
            do {
                let file = try ImageTemporaryFile()
                guard await disk.copy(forKey: key, revision: revision, to: file.url) else {
                    await lease.release()
                    return ImageLoadValue(image: nil)
                }
                let image = try await prepare(.file(file))
                await lease.release()
                ImageCacheMetrics.shared.mark("cache", key: key, outcome: "diskFile", bytes: size)
                return ImageLoadValue(image: image)
            } catch {
                await lease.release()
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                return ImageLoadValue(image: nil)
            }
        }
        let lease = try await resources.decodeBytes.acquire(max(1, size))
        do {
            guard let data = await disk.read(forKey: key, revision: revision, maxBytes: max(1, size)) else {
                await lease.release()
                return ImageLoadValue(image: nil)
            }
            let image = try await prepare(.data(data))
            await lease.release()
            ImageCacheMetrics.shared.mark("cache", key: key, outcome: "disk", bytes: data.count)
            return ImageLoadValue(image: image)
        } catch {
            await lease.release()
            if error is CancellationError || Task.isCancelled { throw CancellationError() }
            // 손상된 캐시 데이터는 네트워크 재요청으로 복구한다.
            return ImageLoadValue(image: nil)
        }
    }

    func stored(_ data: Data) async throws -> ImageLoadValue {
        if data.count > min(resources.limits.decodeBytes, resources.limits.writeBytes) {
            let lease = try await resources.files.acquire()
            do {
                let file = try ImageTemporaryFile()
                try await resources.io.withPermit(kind: .write) { try data.write(to: file.url, options: .atomic) }
                let image = try await prepare(.file(file))
                return ImageLoadValue(image: image, payload: .file(file), release: { await lease.release() })
            } catch { await lease.release(); throw error }
        }
        let write = try await resources.writeBytes.acquire(max(1, data.count))
        let decode: ImageStageGate.Lease
        do { decode = try await resources.decodeBytes.acquire(max(1, data.count)) }
        catch { await write.release(); throw error }
        do {
            let image = try await prepare(.data(data))
            await decode.release()
            return ImageLoadValue(image: image, payload: .data(data), release: { await write.release() })
        } catch { await decode.release(); await write.release(); throw error }
    }

    private func prepare(_ payload: ImageCachePayload) async throws -> UIImage {
        try await resources.decode.withPermit { [self] in
            let result: UIImage?
            switch payload {
            case .data(let data): result = decoder(data)
            case .file(let file):
                result = try await resources.io.withPermit(kind: .read) { [fileDecoder] in fileDecoder(file.url) }
            }
            try Task.checkCancellation()
            guard let result else { throw ImageCachePipelineError.invalidImageData }
            ImageCacheMetrics.shared.mark("image.prepared", bytes: Int(result.size.width * result.scale) * Int(result.size.height * result.scale) * 4)
            return result
        }
    }
}
