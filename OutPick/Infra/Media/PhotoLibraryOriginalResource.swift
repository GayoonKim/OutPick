import Foundation
import ImageIO
import Photos
import UniformTypeIdentifiers

/// 캐시 확장자 대신 실제 이미지 컨테이너를 읽는다. 픽셀 디코딩·재인코딩은 하지 않는다.
enum PhotoLibraryOriginalResource {
    static func creationOptions(fileURL: URL, isVideo: Bool) throws -> PHAssetResourceCreationOptions {
        let options = PHAssetResourceCreationOptions()
        options.shouldMoveFile = false
        if isVideo {
            let type = try videoType(fileURL: fileURL)
            if #available(iOS 26, *) { options.contentType = type }
            else { options.uniformTypeIdentifier = type.identifier }
            options.originalFilename = "OutPick-\(UUID()).\(type == .quickTimeMovie ? "mov" : "mp4")"
            return options
        }
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, [
            kCGImageSourceShouldCache: false
        ] as CFDictionary),
              let identifier = CGImageSourceGetType(source) as String?,
              let type = UTType(identifier), type.conforms(to: .image),
              let ext = type.preferredFilenameExtension else {
            throw PhotoLibrarySaveError.saveFailed
        }
        if #available(iOS 26, *) { options.contentType = type }
        else { options.uniformTypeIdentifier = identifier }
        options.originalFilename = "OutPick-\(UUID().uuidString).\(ext)"
        return options
    }

    /// ISO 컨테이너의 최상위 ftyp만 읽는다. mdat 영상 본문은 읽거나 변환하지 않는다.
    private static func videoType(fileURL: URL) throws -> UTType {
        let file = try FileHandle(forReadingFrom: fileURL)
        defer { try? file.close() }
        let length = try file.seekToEnd()
        var offset: UInt64 = 0
        for _ in 0..<128 {
            guard offset <= length, length - offset >= 8 else { break }
            try file.seek(toOffset: offset)
            let header = try file.read(upToCount: 8) ?? Data()
            guard header.count == 8 else { break }
            var size = header.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
            var headerSize: UInt64 = 8
            if size == 1 {
                let extended = try file.read(upToCount: 8) ?? Data()
                guard extended.count == 8 else { break }
                size = extended.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                headerSize = 16
            } else if size == 0 { size = length - offset }
            guard size >= headerSize, size <= length - offset else { break }
            if String(data: header.suffix(4), encoding: .ascii) == "ftyp" {
                guard size >= headerSize + 8 else { break }
                let brand = try file.read(upToCount: 4) ?? Data()
                let value = String(data: brand, encoding: .ascii) ?? ""
                if value == "qt  " { return .quickTimeMovie }
                if ["isom", "iso2", "iso3", "iso4", "iso5", "iso6", "mp41", "mp42", "avc1", "M4V ", "M4VH", "M4VP"].contains(value) {
                    return .mpeg4Movie
                }
                throw PhotoLibrarySaveError.saveFailed
            }
            offset += size
        }
        // ftyp 없는 구형 MOV 등 이미 확장자가 있는 기존 파일은 기존 Photos 검증을 따른다.
        switch fileURL.pathExtension.lowercased() {
        case "mov": return .quickTimeMovie
        case "mp4", "m4v": return .mpeg4Movie
        default: throw PhotoLibrarySaveError.saveFailed
        }
    }
}

/// Photos는 타입 옵션뿐 아니라 제출 URL의 확장자도 검증한다. 원본 바이트를 그대로 복사한다.
final class PhotoLibraryPreparedResource {
    private static let directory: URL = {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("outpick-media-resources", isDirectory: true)
        // 프로세스당 한 번: 이전 강제 종료가 남긴 전용 사본/링크만 제거한다.
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }()
    let fileURL: URL
    let options: PHAssetResourceCreationOptions
    private let ownedFileURL: URL?

    init(fileURL: URL, isVideo: Bool, preferHardLink: Bool = false) throws {
        options = try PhotoLibraryOriginalResource.creationOptions(fileURL: fileURL, isVideo: isVideo)
        guard let filename = options.originalFilename else {
            self.fileURL = fileURL
            ownedFileURL = nil
            return
        }
        let destination = Self.directory
            .appendingPathComponent("PhotoImport-\(UUID().uuidString)")
            .appendingPathExtension((filename as NSString).pathExtension)
        do {
            if preferHardLink {
                do { try FileManager.default.linkItem(at: fileURL, to: destination) }
                catch { try FileManager.default.copyItem(at: fileURL, to: destination) }
            } else {
                try FileManager.default.copyItem(at: fileURL, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        self.fileURL = destination
        ownedFileURL = destination
    }

    func cleanup() {
        if let ownedFileURL { try? FileManager.default.removeItem(at: ownedFileURL) }
    }

    deinit { cleanup() }
}
