//
//  RepositoryProvider.swift
//  OutPick
//
//  Created by 김가윤 on 12/17/25.
//

import Foundation

final class RepositoryProvider {
    static let shared = RepositoryProvider()

    // MARK: - Lookbook Repositories (Protocol 타입으로 노출)
    let brandRepository: BrandRepositoryProtocol
    let seasonRepository: SeasonRepositoryProtocol
    let postRepository: PostRepositoryProtocol
    let tagRepository: TagRepositoryProtocol
    let commentRepository: CommentRepositoryProtocol
    let replacementRepository: ReplacementRepositoryProtocol
    let postUserStateRepository: PostUserStateRepositoryProtocol

    // MARK: - Services
    let storageService: StorageServiceProtocol

    /// 기본값은 Firestore/Firebase 구현체로 구성합니다.
    /// - Note: ViewModel은 구체 구현체(Firestore*)가 아닌 Protocol 타입만 의존하도록 유지하는 것을 권장합니다.
    /// - Important: 테스트에서는 Mock 구현체를 주입해 `RepositoryProvider` 인스턴스를 별도로 만들어 사용하세요.
    init(
        brandRepository: BrandRepositoryProtocol = FirestoreBrandRepository(),
        seasonRepository: SeasonRepositoryProtocol = FirestoreSeasonRepository(),
        postRepository: PostRepositoryProtocol = FirestorePostRepository(),
        tagRepository: TagRepositoryProtocol = FirestoreTagRepository(),
        commentRepository: CommentRepositoryProtocol = FirestoreCommentRepository(),
        replacementRepository: ReplacementRepositoryProtocol = FirestoreReplacementRepository(),
        postUserStateRepository: PostUserStateRepositoryProtocol = FirestorePostUserStateRepository(),
        storageService: StorageServiceProtocol = FirebaseStorageService()
    ) {
        self.brandRepository = brandRepository
        self.seasonRepository = seasonRepository
        self.postRepository = postRepository
        self.tagRepository = tagRepository
        self.commentRepository = commentRepository
        self.replacementRepository = replacementRepository
        self.postUserStateRepository = postUserStateRepository
        self.storageService = storageService
    }
}
