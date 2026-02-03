import Foundation
import FirebaseFirestore

struct BrandDTO: Codable {
    @DocumentID var id: String?

    let name: String

    /// (호환) 예전 단일 경로 필드. 앞으로는 썸네일을 넣는 용도로 유지 권장
    let logoPath: String?

    /// (신규) 썸네일/원본 분리
    let logoThumbPath: String?
    let logoOriginalPath: String?

    let isFeatured: Bool?
    let likeCount: Int?
    let viewCount: Int?
    let popularScore: Double?
    let updatedAt: Timestamp?

    func toDomain() throws -> Brand {
        guard let id else { throw MappingError.missingDocumentID }

        let metrics = BrandMetrics(
            likeCount: likeCount ?? 0,
            viewCount: viewCount ?? 0,
            popularScore: popularScore ?? 0
        )

        // 1) 썸네일: 신규 필드 우선, 없으면 기존 logoPath로 폴백
        let resolvedThumbPath = logoThumbPath ?? logoPath

        // 2) 원본: 신규 필드만 사용(없으면 nil)
        let resolvedOriginalPath = logoOriginalPath

        return Brand(
            id: BrandID(value: id),
            name: name,
            logoThumbPath: resolvedThumbPath,
            logoOriginalPath: resolvedOriginalPath,
            isFeatured: isFeatured ?? false,
            metrics: metrics,
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
