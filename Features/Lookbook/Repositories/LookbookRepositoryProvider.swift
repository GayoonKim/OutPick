//
//  RepositoryProvider.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation
import FirebaseFirestore

final class LookbookRepositoryProvider {
    static let shared = LookbookRepositoryProvider()

    // MARK: - Lookbook Repositories (Protocol 타입으로 노출)
    let brandRepository: BrandRepositoryProtocol

    let seasonRepository: SeasonRepositoryProtocol
    let seasonCoverThumbnailPolicy: ThumbnailPolicy
    let seasonImportRepository: SeasonImportRequestingRepository
    let seasonImportJobRepository: SeasonImportJobRepositoryProtocol

    let postRepository: PostRepositoryProtocol

    let tagRepository: TagRepositoryProtocol
    let tagAliasRepository: TagAliasRepositoryProtocol
    let tagConceptRepository: TagConceptRepositoryProtocol

    let commentRepository: CommentRepositoryProtocol

    let replacementRepository: ReplacementRepositoryProtocol

    let postUserStateRepository: PostUserStateRepositoryProtocol

    // MARK: - Services
    /// 브랜드 로고 이미지 로더(단일 인스턴스 공유)
    /// - Note: View/VM에서 `BrandImageCache()`를 새로 만들지 말고, provider의 이 인스턴스를 주입해 사용합니다.
    let brandImageCache: any BrandImageCacheProtocol

    let brandStore: BrandStoringRepository
    let storageService: StorageServiceProtocol
    let thumbnailer: ImageThumbnailing
    let imageCachePipeline: ImageCachePipeline

    init(
        brandRepository: BrandRepositoryProtocol = FirestoreBrandRepository(),
        brandStore: BrandStoringRepository = CloudFunctionsBrandStore(),

        seasonRepository: SeasonRepositoryProtocol? = nil,
        seasonCoverThumbnailPolicy: ThumbnailPolicy = ThumbnailPolicies.seasonCover,
        seasonImportRepository: SeasonImportRequestingRepository = CloudFunctionsSeasonImportRepository(),
        seasonImportJobRepository: SeasonImportJobRepositoryProtocol = FirestoreSeasonImportJobRepository(),

        postRepository: PostRepositoryProtocol = FirestorePostRepository(),

        tagRepository: TagRepositoryProtocol = FirestoreTagRepository(),
        tagAliasRepository: TagAliasRepositoryProtocol = FirestoreTagAliasRepository(),
        tagConceptRepository: TagConceptRepositoryProtocol = FirestoreTagConceptRepository(),

        commentRepository: CommentRepositoryProtocol = FirestoreCommentRepository(),

        replacementRepository: ReplacementRepositoryProtocol = FirestoreReplacementRepository(),

        postUserStateRepository: PostUserStateRepositoryProtocol = FirestorePostUserStateRepository(),

        brandImageCache: (any BrandImageCacheProtocol)? = nil,
        imageCachePipeline: ImageCachePipeline? = nil,
        storageService: StorageServiceProtocol = LookbookStorageService(),
        thumbnailer: ImageThumbnailing = ImageIOThumbnailer()
    ) {
        self.storageService = storageService
        self.thumbnailer = thumbnailer
        let resolvedImageCachePipeline = imageCachePipeline ?? ImageCachePipeline { [storageService] path, maxBytes in
            try await storageService.downloadImage(from: path, maxSize: maxBytes)
        }
        self.imageCachePipeline = resolvedImageCachePipeline

        // provider가 가진 pipeline/storage를 그대로 사용
        self.brandImageCache = brandImageCache
            ?? BrandImageCache(storage: storageService, pipeline: resolvedImageCachePipeline)

        self.brandRepository = brandRepository
        self.postRepository = postRepository

        self.tagRepository = tagRepository
        self.tagAliasRepository = tagAliasRepository
        self.tagConceptRepository = tagConceptRepository

        self.commentRepository = commentRepository
        self.replacementRepository = replacementRepository
        self.postUserStateRepository = postUserStateRepository

        // Provider가 season repo를 조립할 때 thumbnailer/policy를 공유 주입
        self.seasonRepository = seasonRepository
            ?? FirestoreSeasonRepository(
                storage: storageService,
                thumbnailer: thumbnailer,
                coverThumbnailPolicy: seasonCoverThumbnailPolicy
            )
        self.seasonCoverThumbnailPolicy = seasonCoverThumbnailPolicy
        self.seasonImportRepository = seasonImportRepository
        self.seasonImportJobRepository = seasonImportJobRepository
        self.brandStore = brandStore
    }
}
