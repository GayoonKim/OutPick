import Foundation
import PhotosUI
import AVFoundation

enum ChatPreparedSelectionChunk {
    case images([ProcessedImage])
    case video(PreparedVideo)
    case failedVideo(ChatMediaSelection.Source)
    case failedImages([ChatMediaSelection.Source])
}

/// 파일 확보 barrier와 순서 보존 준비를 소유한다. 화면은 완성 chunk만 받아 표현한다.
final class ChatMediaSelectionUseCase {
    private let repository: ChatMediaSelectionRepository
    let limits: ChatMediaPipelineLimits
    private let prepareImage: @Sendable (URL, Int) throws -> ProcessedImage
    private let selectionTurns = ChatMediaUploadTurnQueue()
    private let acquisitionTurns: ChatMediaUploadTurnQueue

    func beginSelection(_ id: String) async throws {
        try await selectionTurns.acquire(lane: .images, uploadID: id)
    }

    func endSelection(_ id: String) async {
        await selectionTurns.release(lane: .images, uploadID: id)
    }

    func restoredSelections(roomID: String, senderUID: String, excluding activeIDs: Set<String>) async throws -> [ChatMediaSelection] {
        try await repository.restored(roomID: roomID, senderUID: senderUID, excluding: activeIDs)
    }

    func selection(_ id: String) async throws -> ChatMediaSelection? { try await repository.load(id) }
    func deleteSelection(_ id: String) async throws { try await repository.remove(id) }

    func preserveFailedVideo(_ source: ChatMediaSelection.Source, id: String, roomID: String, senderUID: String) async throws {
        let directory = try await repository.directory(id)
        let target = directory.appendingPathComponent(URL(fileURLWithPath: source.path).lastPathComponent)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: source.path), to: target)
        try await repository.save(.init(selectionID: id, roomID: roomID, senderUID: senderUID, createdAt: Date(),
            selectionSources: [.init(index: source.index, path: target.path, isVideo: true)]))
    }

    func preserveFailedImages(_ sources: [ChatMediaSelection.Source], id: String, roomID: String,
                              senderUID: String) async throws {
        let directory = try await repository.directory(id)
        var owned: [ChatMediaSelection.Source] = []
        for source in sources {
            let original = URL(fileURLWithPath: source.path)
            let target = directory.appendingPathComponent(String(source.index)).appendingPathExtension(original.pathExtension)
            // 같은 child 원장 저장을 재시도해도 이미 복사한 파일을 다시 덮어쓰지 않는다.
            if !FileManager.default.fileExists(atPath: target.path) {
                try FileManager.default.copyItem(at: original, to: target)
            }
            owned.append(.init(index: source.index, path: target.path, isVideo: false))
        }
        try await repository.save(.init(selectionID: id, roomID: roomID, senderUID: senderUID,
            createdAt: Date(), selectionSources: owned))
    }

    init(repository: ChatMediaSelectionRepository, limits: ChatMediaPipelineLimits = .init(),
         prepareImage: @escaping @Sendable (URL, Int) throws -> ProcessedImage = {
             try ChatImageTransportSourceNormalizer.prepare(sourceURL: $0, index: $1)
         }) {
        self.repository = repository
        precondition(limits.acquisition > 0 && limits.imagePreparation > 0)
        self.limits = limits
        self.prepareImage = prepareImage
        acquisitionTurns = ChatMediaUploadTurnQueue(imageLimit: limits.acquisition)
    }

    func acquire(_ results: [PHPickerResult], roomID: String, senderUID: String, id: String) async throws -> ChatMediaSelection {
        try await acquire(sourceCount: results.count, roomID: roomID, senderUID: senderUID, id: id) { index, directory in
            try await ChatMediaSourceAcquisition.acquire(results[index], index: index, directory: directory)
        }
    }

    func acquire(sourceCount: Int, roomID: String, senderUID: String, id: String,
        sourceAt: @escaping @Sendable (Int, URL) async throws -> ChatMediaSelection.Source) async throws -> ChatMediaSelection {
        #if DEBUG
        let acquisitionStarted = ProcessInfo.processInfo.systemUptime
        print("[MediaQA] event=acquisition_started selectionID=\(id) count=\(sourceCount) concurrency=\(limits.acquisition) uptime=\(acquisitionStarted) thermal=\(ProcessInfo.processInfo.thermalState.rawValue)")
        #endif
        // 빈 source 원장은 확보 도중 앱 종료 시 잔여 파일을 정리하는 용도이며 버블로 표시하지 않는다.
        try await repository.save(.init(selectionID: id, roomID: roomID, senderUID: senderUID,
            createdAt: Date(), selectionSources: []))
        #if DEBUG
        print("[MediaQA] event=acquisition_ledger_saved selectionID=\(id) uptime=\(ProcessInfo.processInfo.systemUptime)")
        #endif
        do {
            let directory = try await repository.directory(id)
            #if DEBUG
            print("[MediaQA] event=acquisition_directory_ready selectionID=\(id) uptime=\(ProcessInfo.processInfo.systemUptime)")
            #endif
            let sources = try await withThrowingTaskGroup(of: ChatMediaSelection.Source.self) { group in
                var next = 0
                var output: [ChatMediaSelection.Source] = []
                func add(_ index: Int) {
                    #if DEBUG
                    let scheduled = ProcessInfo.processInfo.systemUptime
                    print("[MediaQA] event=source_scheduled selectionID=\(id) index=\(index) uptime=\(scheduled) sinceAcquisitionMs=\((scheduled - acquisitionStarted) * 1000)")
                    #endif
                    group.addTask { [acquisitionTurns] in
                        let token = UUID().uuidString
                        try await acquisitionTurns.acquire(lane: .images, uploadID: token)
                        #if DEBUG
                        let admitted = ProcessInfo.processInfo.systemUptime
                        print("[MediaQA] event=source_slot_acquired selectionID=\(id) index=\(index) uptime=\(admitted) queueMs=\((admitted - scheduled) * 1000)")
                        #endif
                        do {
                            let source = try await sourceAt(index, directory)
                            await acquisitionTurns.release(lane: .images, uploadID: token)
                            return source
                        } catch {
                            await acquisitionTurns.release(lane: .images, uploadID: token)
                            throw error
                        }
                    }
                }
                while next < min(sourceCount, limits.acquisition) { add(next); next += 1 }
                while let source = try await group.next() {
                    output.append(source)
                    if next < sourceCount { add(next); next += 1 }
                }
                return output.sorted { $0.index < $1.index }
            }
            #if DEBUG
            print("[MediaQA] event=acquisition_sources_completed selectionID=\(id) uptime=\(ProcessInfo.processInfo.systemUptime)")
            #endif
            try Task.checkCancellation()
            let selection = ChatMediaSelection(selectionID: id, roomID: roomID, senderUID: senderUID,
                createdAt: Date(), selectionSources: sources)
            try await repository.save(selection)
            return selection
        } catch {
            // Task Group의 자식이 모두 종료된 뒤 디렉터리를 지워 늦은 복사와 경합하지 않는다.
            try? await repository.remove(id)
            throw error
        }
    }

    func process(
        _ original: ChatMediaSelection,
        onChunk: @escaping (String, ChatPreparedSelectionChunk) async throws -> Void,
        onCommitted: @escaping (String) async -> Void
    ) async throws -> Int {
        try await prepare(original, onChunk: onChunk, onCommitted: onCommitted)
    }

    private func prepare(
        _ original: ChatMediaSelection,
        onChunk: @escaping (String, ChatPreparedSelectionChunk) async throws -> Void,
        onCommitted: @escaping (String) async -> Void
    ) async throws -> Int {
        var selection = original
        var current: [ProcessedImage] = []
        var currentIndices: [Int] = []
        var rejected = 0
        var failedImages: [ChatMediaSelection.Source] = []
        var transientFiles: [URL] = []
        defer { transientFiles.forEach { try? FileManager.default.removeItem(at: $0) } }

        func deliver(_ indices: [Int], _ chunk: ChatPreparedSelectionChunk) async throws {
            try Task.checkCancellation()
            let messageID = UUID().uuidString
            selection.pendingChunk = .init(messageID: messageID, indices: indices)
            try await repository.save(selection)
            do {
                try await onChunk(messageID, chunk)
                guard try await repository.childPreserved(messageID) else { throw MediaError.failedToConvertImage }
                selection.selectionSources.removeAll { indices.contains($0.index) }
                selection.pendingChunk = nil
                try await repository.save(selection)
            } catch {
                throw error
            }
            await onCommitted(messageID)
            let ownedFiles: [URL]
            switch chunk {
            case .images(let pairs): ownedFiles = pairs.flatMap { [$0.originalFileURL] + [$0.thumbFileURL].compactMap { $0 } }
            case .video(let video): ownedFiles = [video.compressedFileURL] + [video.thumbnailFileURL].compactMap { $0 }
            case .failedVideo, .failedImages: ownedFiles = []
            }
            ownedFiles.forEach { try? FileManager.default.removeItem(at: $0) }
            transientFiles.removeAll { ownedFiles.contains($0) }
        }

        // 이미지/영상의 상대 준비 순서는 선택 순서를 유지한다. 같은 연속 이미지 구간만 병렬 처리한다.
        let sources = original.selectionSources.sorted { $0.index < $1.index }
        var cursor = 0
        while cursor < sources.count {
            try Task.checkCancellation()
            if sources[cursor].isVideo {
                let source = sources[cursor]
                let video: PreparedVideo?
                do { video = try await Self.prepareVideo(source) }
                catch is CancellationError { throw CancellationError() }
                catch { video = nil }
                if let video {
                    transientFiles.append(video.compressedFileURL)
                    if let thumbnail = video.thumbnailFileURL { transientFiles.append(thumbnail) }
                    try await deliver([source.index], .video(video))
                } else {
                    try await deliver([source.index], .failedVideo(source))
                }
                cursor += 1
                continue
            }
            let start = cursor
            while cursor < sources.count, !sources[cursor].isVideo, cursor - start < limits.imagePreparation { cursor += 1 }
            let batch = Array(sources[start..<cursor])
            let prepared = await withTaskGroup(of: (Int, ProcessedImage?).self) { group in
                for source in batch {
                    group.addTask { [prepareImage] in
                        let result: ProcessedImage? = autoreleasepool { () -> ProcessedImage? in
                            do { return try prepareImage(URL(fileURLWithPath: source.path), source.index) }
                            catch {
                                #if DEBUG
                                let failure = error as NSError
                                print("[MediaQA] event=image_prepare_failed selectionID=\(original.selectionID) index=\(source.index) domain=\(failure.domain) code=\(failure.code)")
                                #endif
                                return nil as ProcessedImage?
                            }
                        }
                        return (source.index, result)
                    }
                }
                var output: [(Int, ProcessedImage?)] = []
                for await value in group { output.append(value) }
                return output.sorted { $0.0 < $1.0 }
            }
            transientFiles.append(contentsOf: prepared.compactMap { $0.1?.originalFileURL })
            transientFiles.append(contentsOf: prepared.compactMap { $0.1?.thumbFileURL })
            try Task.checkCancellation()
            for (index, pair) in prepared {
                guard let pair else {
                    rejected += 1
                    if let source = batch.first(where: { $0.index == index }) { failedImages.append(source) }
                    continue
                }
                if !current.isEmpty && (current.count == 30 || current.reduce(0, { $0 + $1.bytesOriginal }) + pair.bytesOriginal > ChatMediaSelectionChunker.maxAggregateBytes) {
                    try await deliver(currentIndices, .images(ChatMediaSelectionChunker.chunks(current)[0]))
                    current = []; currentIndices = []
                }
                current.append(pair); currentIndices.append(index)
                if current.count == 30 {
                    try await deliver(currentIndices, .images(ChatMediaSelectionChunker.chunks(current)[0]))
                    current = []; currentIndices = []
                }
            }
        }
        if !current.isEmpty {
            try await deliver(currentIndices, .images(ChatMediaSelectionChunker.chunks(current)[0]))
        }
        // 실패 원본도 child 원장에 보존한 뒤에만 parent 소유권을 해제한다.
        for offset in stride(from: 0, to: failedImages.count, by: ChatPhotoSizePolicy.maximumImagesPerMessage) {
            let group = Array(failedImages[offset..<min(offset + ChatPhotoSizePolicy.maximumImagesPerMessage, failedImages.count)])
            try await deliver(group.map(\.index), .failedImages(group))
        }
        if selection.selectionSources.isEmpty { try await repository.remove(selection.selectionID) }
        return rejected
    }

    private static func prepareVideo(_ source: ChatMediaSelection.Source) async throws -> PreparedVideo {
        let url = try await AVAssetExportVideoCompressor.compress720pMP4(inputURL: URL(fileURLWithPath: source.path))
        do {
            try Task.checkCancellation()
            let asset = AVAsset(url: url)
            let duration = CMTimeGetSeconds(asset.duration)
            let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            let track = asset.tracks(withMediaType: .video).first
            let dimensions = track.map { $0.naturalSize.applying($0.preferredTransform) } ?? .zero
            let digest = try ChatMediaFileDigest.sha256(url)
            let thumb = try await DefaultMediaProcessingService.makeChatVideoThumbnailFile(url: url)
            return PreparedVideo(compressedFileURL: url, thumbnailData: Data(),
                sha256: digest, duration: duration,
                width: Int(abs(dimensions.width)), height: Int(abs(dimensions.height)), sizeBytes: size,
                approxBitrateMbps: duration > 0 ? Double(size) * 8 / duration / 1_000_000 : 0, preset: .standard720,
                thumbnailFileURL: thumb)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }
}
