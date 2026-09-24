import Foundation

/// 기본 pipeline들이 공유하는 단계별 예산. 예약은 네트워크 permit 전에 수행한다.
final class ImagePipelineResources {
    static let shared = ImagePipelineResources()
    let limits: ImagePipelineLimits
    let network: ImageStageGate
    let decode: ImageStageGate
    // 앱의 캐시/로컬 I/O 제한이다. SDK 다운로드의 임시 파일 쓰기는 network/files가 제한한다.
    let io: ImageStageGate
    let decodeBytes: ImageStageGate
    let writeBytes: ImageStageGate
    let files: ImageStageGate

    init(limits: ImagePipelineLimits = ImagePipelineLimits()) {
        self.limits = limits
        network = ImageStageGate(limits.downloads, name: "network")
        decode = ImageStageGate(limits.decodes, name: "decode")
        io = ImageStageGate(limits.diskOperations, name: "diskIO", maxWrites: limits.diskWrites)
        decodeBytes = ImageStageGate(limits.decodeBytes, name: "decodeBytes")
        writeBytes = ImageStageGate(limits.writeBytes, name: "writeBytes")
        // 전송·디코딩·저장 대기까지 포함한 파일 입장 수를 제한해 임시 파일 누적을 막는다.
        files = ImageStageGate(limits.downloads, name: "temporaryFiles")
    }

    func reprioritize() {
        Task {
            await network.reprioritize()
            await decode.reprioritize()
            await io.reprioritize()
            await decodeBytes.reprioritize()
            await writeBytes.reprioritize()
            await files.reprioritize()
        }
    }
}
