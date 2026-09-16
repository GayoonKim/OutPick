import Foundation

/// 기본 pipeline들이 공유하는 단계별 예산. 예약은 네트워크 permit 전에 수행한다.
final class ImagePipelineResources {
    static let shared = ImagePipelineResources()
    let limits: ImagePipelineLimits
    let network: ImageStageGate
    let decode: ImageStageGate
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
        // 임시 파일도 무제한 누적하지 않는다. 파일 경로의 총 입장 수는 다운로드 폭과 같다.
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
