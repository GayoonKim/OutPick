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
    let brandStore: BrandStoringRepository
    let storageService: StorageServiceProtocol
    let thumbnailer: ImageThumbnailing

    /// 기본값은 Firestore/Firebase 구현체로 구성합니다.
    /// - Important: 테스트에서는 Mock 구현체를 주입해 `RepositoryProvider` 인스턴스를 별도로 만들어 사용하세요.
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
        
        storageService: StorageServiceProtocol = FirebaseStorageService(),
        thumbnailer: ImageThumbnailing = ImageIOThumbnailer()
    ) {
        self.storageService = storageService
        self.thumbnailer = thumbnailer

        self.brandRepository = brandRepository
        
        self.postRepository = postRepository
        
        self.tagRepository = tagRepository
        self.tagAliasRepository = tagAliasRepository
        self.tagConceptRepository = tagConceptRepository
        
        self.commentRepository = commentRepository
        
        self.replacementRepository = replacementRepository
        
        self.postUserStateRepository = postUserStateRepository

        // ✅ Provider가 season repo를 조립할 때 thumbnailer/policy를 공유 주입
        self.seasonRepository = seasonRepository ?? FirestoreSeasonRepository( storage: storageService, thumbnailer: thumbnailer, coverThumbnailPolicy: seasonCoverThumbnailPolicy)
        self.seasonCoverThumbnailPolicy = seasonCoverThumbnailPolicy
        self.brandStore = brandStore
    }
}
