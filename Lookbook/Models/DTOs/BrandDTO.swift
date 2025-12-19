import Foundation
import FirebaseFirestore

struct BrandDTO: Codable {
    @DocumentID var id: String?

    let name: String
    /// Firebase Storage 경로 (예: "brands/{brandID}/logo.jpg")
    let logoPath: String?

    /// 운영자/편집자 픽 여부(홈 상단 고정 노출 등)
    let isFeatured: Bool?

    /// 좋아요 수(좋아요순 정렬/표시용)
    let likeCount: Int?

    /// 조회 수(조회순 정렬/표시용)
    let viewCount: Int?

    /// 인기 점수(인기순 정렬/표시용)
    /// - Note: 인기 점수는 정책에 따라 Int/Double 중 하나로 운영될 수 있습니다.
    ///         현재 Domain의 BrandMetrics가 Int를 사용한다는 전제입니다.
    let popularScore: Double?

    let updatedAt: Timestamp?

    /// Firestore DTO -> Domain 변환
    /// - Note: 스키마 변경에 대비해 optional을 허용하고, 여기서 기본값을 채웁니다.
    func toDomain() throws -> Brand {
        guard let id else { throw MappingError.missingDocumentID }

        let metrics = BrandMetrics(
            likeCount: likeCount ?? 0,
            viewCount: viewCount ?? 0,
            popularScore: popularScore ?? 0
        )

        return Brand(
            id: BrandID(value: id),
            name: name,
            logoPath: logoPath,
            isFeatured: isFeatured ?? false,
            metrics: metrics,
            updatedAt: updatedAt?.dateValue() ?? Date(timeIntervalSince1970: 0)
        )
    }
}
