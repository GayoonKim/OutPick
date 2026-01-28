//
//  RepositoryProvider.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation
import FirebaseFirestore

final class RepositoryProvider {
    static let shared = RepositoryProvider()

    // MARK: - Lookbook Repositories (Protocol 타입으로 노출)
    let brandRepository: BrandRepositoryProtocol

    let seasonRepository: SeasonRepositoryProtocol
    let seasonCoverThumbnailPolicy: ThumbnailPolicy

    let postRepository: PostRepositoryProtocol

    let tagRepository: TagRepositoryProtocol
    let tagAliasRepository: TagAliasRepositoryProtocol
    let tagConceptRepository: TagConceptRepositoryProtocol

    let commentRepository: CommentRepositoryProtocol

    let replacementRepository: ReplacementRepositoryProtocol

    let postUserStateRepository: PostUserStateRepositoryProtocol

    // MARK: - Services
    /// 브랜드 로고 이미지 로더(단일 인스턴스 공유)
    /// - Note: View/VM에서 `BrandLogoImageStore()`를 새로 만들지 말고, provider의 이 인스턴스를 주입해 사용합니다.
    let brandLogoImageLoader: any ImageLoading

    /// 이미지 캐시(단일 인스턴스 공유)
    let imageCache: ImageCaching

    let brandStore: BrandStoringRepository
    let storageService: StorageServiceProtocol
    let thumbnailer: ImageThumbnailing

    init(
        brandRepository: BrandRepositoryProtocol = FirestoreBrandRepository(),
        brandStore: BrandStoringRepository = FirestoreBrandStore(),

        seasonRepository: SeasonRepositoryProtocol? = nil,
        seasonCoverThumbnailPolicy: ThumbnailPolicy = ThumbnailPolicies.seasonCover,

        postRepository: PostRepositoryProtocol = FirestorePostRepository(),

        tagRepository: TagRepositoryProtocol = FirestoreTagRepository(),
        tagAliasRepository: TagAliasRepositoryProtocol = FirestoreTagAliasRepository(),
        tagConceptRepository: TagConceptRepositoryProtocol = FirestoreTagConceptRepository(),

        commentRepository: CommentRepositoryProtocol = FirestoreCommentRepository(),

        replacementRepository: ReplacementRepositoryProtocol = FirestoreReplacementRepository(),

        postUserStateRepository: PostUserStateRepositoryProtocol = FirestorePostUserStateRepository(),

        brandLogoImageLoader: (any ImageLoading)? = nil,
        imageCache: ImageCaching = MemoryImageCache(),
        storageService: StorageServiceProtocol = FirebaseStorageService(),
        thumbnailer: ImageThumbnailing = ImageIOThumbnailer()
    ) {
        self.storageService = storageService
        self.thumbnailer = thumbnailer
        self.imageCache = imageCache

        // ✅ provider가 가진 cache/storage를 그대로 사용
        self.brandLogoImageLoader = brandLogoImageLoader
            ?? BrandLogoImageStore(cache: imageCache, storage: storageService)

        self.brandRepository = brandRepository
        self.postRepository = postRepository

        self.tagRepository = tagRepository
        self.tagAliasRepository = tagAliasRepository
        self.tagConceptRepository = tagConceptRepository

        self.commentRepository = commentRepository
        self.replacementRepository = replacementRepository
        self.postUserStateRepository = postUserStateRepository

        // ✅ Provider가 season repo를 조립할 때 thumbnailer/policy를 공유 주입
        self.seasonRepository = seasonRepository
            ?? FirestoreSeasonRepository(
                storage: storageService,
                thumbnailer: thumbnailer,
                coverThumbnailPolicy: seasonCoverThumbnailPolicy
            )
        self.seasonCoverThumbnailPolicy = seasonCoverThumbnailPolicy
        self.brandStore = brandStore
    }
}
