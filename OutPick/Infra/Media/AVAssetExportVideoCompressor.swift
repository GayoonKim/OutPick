import Foundation
@preconcurrency import AVFoundation

// MARK: - Swift 6 Concurrency (실서비스용 최소 우회)
// Swift 6에서 AVAssetExportSession은 Sendable이 아니므로 exportAsynchronously 콜백(클로저)에서 캡처될 때 오류가 날 수 있습니다.
// 이 압축기는 exporter를 함수 내부에서만 생성/사용하고 외부로 공유하지 않으므로,
// 컴파일러의 Sendable 체크만 최소 범위로 우회(@unchecked)합니다.
extension AVAssetExportSession: @unchecked @retroactive Sendable {}

// MARK: - Test Only: AVAssetExportSession 기반 720p 압축기

/// FYVideoCompressor 대신, iOS 순정 `AVAssetExportSession` 프리셋으로 720p 압축을 테스트하기 위한 구현
/// - 주의: 실제 제품 적용 전에는 결과 품질/회전 메타/오디오 싱크/진행률 표시 등 케이스를 충분히 확인해야 함
enum AVAssetExportVideoCompressor {

    enum ExportError: Error {
        case cannotCreateExporter
        case unsupportedFileType
        case failedToExport(underlying: Error?)
    }

    /// 720p 프리셋으로 MP4 파일을 생성
    /// - Parameters:
    ///   - inputURL: 원본 비디오 파일 URL
    /// - Returns: 압축된 비디오 파일 URL
    static func compress720pMP4(
        inputURL: URL
    ) async throws -> URL {
        let asset = AVAsset(url: inputURL)

        // 720p 프리셋(1280x720)
        let preset = AVAssetExportPreset1280x720

        guard let exporter = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ExportError.cannotCreateExporter
        }

        // 출력 파일 타입
        let outputType: AVFileType = .mp4
        guard exporter.supportedFileTypes.contains(outputType) else {
            throw ExportError.unsupportedFileType
        }

        // 임시 출력 경로 생성
        let fm = FileManager.default
        let outDir = fm.temporaryDirectory.appendingPathComponent("export-720p", isDirectory: true)
        try? fm.createDirectory(at: outDir, withIntermediateDirectories: true)

        let outURL = outDir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")
        if fm.fileExists(atPath: outURL.path) {
            try? fm.removeItem(at: outURL)
        }

        exporter.outputURL = outURL
        exporter.outputFileType = outputType
        exporter.shouldOptimizeForNetworkUse = true

        // export 실행
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exporter.exportAsynchronously {
                // exporter의 상태/에러 접근은 메인 스레드에서만
                DispatchQueue.main.async {
                    switch exporter.status {
                    case .completed:
                        continuation.resume(returning: ())

                    case .failed, .cancelled:
                        continuation.resume(throwing: ExportError.failedToExport(underlying: exporter.error))

                    default:
                        // waiting/exporting/unknown 등: 완료 콜백인데 completed가 아닌 경우는 실패로 처리
                        continuation.resume(throwing: ExportError.failedToExport(underlying: exporter.error))
                    }
                }
            }
        }

        return outURL
    }
}
