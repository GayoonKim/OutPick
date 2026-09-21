import Foundation
import UIKit

/// 저장용 변환 형식은 소비자가 선택한다. 기본 pipeline에는 재인코딩을 추가하지 않는다.
struct ImageCachePromotionEncoding: Sendable {
    let maximumBytes: Int
    let encode: @Sendable (UIImage) -> Data?
}

extension ImagePipelineProcessor {
    /// 화면 반환과 분리하며 출력 예산을 확보한 뒤 공용 준비 슬롯에서 변환한다.
    func encoded(_ image: UIImage, using encoding: ImageCachePromotionEncoding) async throws -> ImageLoadValue {
        let lease = try await resources.writeBytes.acquire(encoding.maximumBytes)
        do {
            let data = try await resources.decode.withPermit {
                try Task.checkCancellation()
                guard let data = autoreleasepool(invoking: { encoding.encode(image) }) else {
                    throw ImageCachePipelineError.invalidImageData
                }
                guard data.count <= encoding.maximumBytes else { throw ImageCachePipelineError.imageTooLarge }
                try Task.checkCancellation()
                return data
            }
            await lease.reduce(to: max(1, data.count))
            return ImageLoadValue(image: image, payload: .data(data), release: { await lease.release() })
        } catch {
            await lease.release()
            throw error
        }
    }
}
