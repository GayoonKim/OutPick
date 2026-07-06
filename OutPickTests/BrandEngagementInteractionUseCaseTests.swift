//
//  BrandEngagementInteractionUseCaseTests.swift
//  OutPickTests
//
//  Created by Codex on 5/25/26.
//

import Foundation
import Testing
@testable import OutPick

struct BrandEngagementInteractionUseCaseTests {
    @MainActor
    @Test func rapidTapsConvergeToLastStateWithoutExtraServerCall() async throws {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let repository = BrandEngagementRepositorySpy()
        repository.delayFirstCallNanoseconds = 80_000_000
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        store.seedBrand(
            makeBrand(id: brandID, likeCount: 3),
            userState: BrandUserState(
                brandID: brandID,
                userID: userID,
                isLiked: false,
                updatedAt: Date()
            )
        )
        let useCase = BrandEngagementInteractionUseCase(
            repository: repository,
            brandInteractionStore: store
        )

        let firstTask = Task { @MainActor in
            await useCase.toggleLike(
                input: makeInput(brandID: brandID, userID: userID, store: store)
            )
        }

        try await waitUntil {
            store.brandState(for: brandID)?.userState?.isLiked == true
        }
        #expect(store.brandState(for: brandID)?.isMutatingLike == true)

        _ = await useCase.toggleLike(
            input: makeInput(brandID: brandID, userID: userID, store: store)
        )
        _ = await useCase.toggleLike(
            input: makeInput(brandID: brandID, userID: userID, store: store)
        )
        _ = await firstTask.value

        #expect(repository.setLikeInputs == [true])
        #expect(store.brandState(for: brandID)?.userState?.isLiked == true)
        #expect(store.brandState(for: brandID)?.metrics.likeCount == 4)
        #expect(store.brandState(for: brandID)?.isMutatingLike == false)
    }

    @MainActor
    @Test func failureRestoresConfirmedBrandLikeState() async {
        let userID = UserID(value: "user-1")
        let brandID = BrandID(value: "brand-1")
        let repository = BrandEngagementRepositorySpy()
        repository.errorToThrow = NSError(domain: "BrandEngagementRepositorySpy", code: -1)
        let store = LookbookInteractionStore(
            maxPostStateCount: 10,
            maxCommentStateCount: 10,
            maxBrandStateCount: 10,
            stateRetentionInterval: 60
        )
        store.seedBrand(
            makeBrand(id: brandID, likeCount: 3),
            userState: BrandUserState(
                brandID: brandID,
                userID: userID,
                isLiked: false,
                updatedAt: Date()
            )
        )
        let useCase = BrandEngagementInteractionUseCase(
            repository: repository,
            brandInteractionStore: store
        )

        let outcome = await useCase.toggleLike(
            input: makeInput(brandID: brandID, userID: userID, store: store)
        )

        #expect(outcome.errorMessage == "좋아요를 반영하지 못했어요.")
        #expect(repository.setLikeInputs == [true])
        #expect(store.brandState(for: brandID)?.userState?.isLiked == false)
        #expect(store.brandState(for: brandID)?.metrics.likeCount == 3)
        #expect(store.brandState(for: brandID)?.isMutatingLike == false)
    }

    @MainActor
    private func makeInput(
        brandID: BrandID,
        userID: UserID,
        store: LookbookInteractionStore
    ) -> BrandEngagementInteractionInput {
        let state = store.brandState(for: brandID)
        return BrandEngagementInteractionInput(
            brandID: brandID,
            userID: userID,
            currentUserState: state?.userState,
            currentMetrics: state?.metrics
        )
    }

    private func makeBrand(
        id: BrandID,
        likeCount: Int
    ) -> Brand {
        Brand(
            id: id,
            name: "Brand \(id.value)",
            englishName: nil,
            websiteURL: nil,
            lookbookArchiveURL: nil,
            logoThumbPath: nil,
            logoDetailPath: nil,
            logoOriginalPath: nil,
            isFeatured: false,
            discoveryStatus: .idle,
            lastDiscoveryErrorMessage: nil,
            lastDiscoveryRequestedAt: nil,
            lastDiscoveryCompletedAt: nil,
            metrics: BrandMetrics(
                likeCount: likeCount,
                viewCount: 0,
                popularScore: 0
            ),
            updatedAt: Date()
        )
    }

    @MainActor
    private func waitUntil(
        timeout: TimeInterval = 1,
        _ predicate: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while predicate() == false && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(predicate())
    }
}

@MainActor
private final class BrandEngagementRepositorySpy: BrandEngagementRepositoryProtocol {
    var setLikeInputs: [Bool] = []
    var delayFirstCallNanoseconds: UInt64 = 0
    var errorToThrow: Error?

    func setLike(
        brandID: BrandID,
        isLiked: Bool
    ) async throws -> BrandEngagementResult {
        setLikeInputs.append(isLiked)
        if setLikeInputs.count == 1, delayFirstCallNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayFirstCallNanoseconds)
        }
        if let errorToThrow {
            throw errorToThrow
        }
        return BrandEngagementResult(
            brandID: brandID,
            userID: UserID(value: "user-1"),
            isLiked: isLiked,
            likeCount: isLiked ? 4 : 3
        )
    }
}
