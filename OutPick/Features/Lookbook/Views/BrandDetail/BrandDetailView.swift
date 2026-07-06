//
//  BrandDetailView.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/26.
//

import SwiftUI

struct BrandDetailView: View {
    let brand: Brand
    let brandImageCache: any BrandImageCacheProtocol
    let maxBytes: Int
    let coordinator: LookbookCoordinator
    let shareSheetFactory: (LookbookShareTarget, @escaping (LookbookChatShareViewModel.Completion) -> Void) -> AnyView
    let onShareMove: (LookbookChatShareViewModel.Completion) async throws -> Void

    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @StateObject private var viewModel: BrandDetailViewModel
    @State private var activeShareTarget: LookbookShareTarget?
    @State private var shareCompletion: LookbookChatShareViewModel.Completion?
    @State private var shareMoveErrorMessage: String?
    @State private var didPrepareInitialContent: Bool = false

    init(
        brand: Brand,
        viewModel: BrandDetailViewModel,
        brandImageCache: any BrandImageCacheProtocol,
        coordinator: LookbookCoordinator,
        shareSheetFactory: @escaping (LookbookShareTarget, @escaping (LookbookChatShareViewModel.Completion) -> Void) -> AnyView,
        onShareMove: @escaping (LookbookChatShareViewModel.Completion) async throws -> Void,
        maxBytes: Int = 1_000_000
    ) {
        self.brand = brand
        self.brandImageCache = brandImageCache
        self.coordinator = coordinator
        self.shareSheetFactory = shareSheetFactory
        self.onShareMove = onShareMove
        self.maxBytes = maxBytes
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if shouldBlockInitialLoading {
                initialLoadingView
            } else {
                List {
                    BrandDetailHeaderView(
                        brand: brand,
                        likeCount: viewModel.brandMetrics?.likeCount ?? brand.metrics.likeCount,
                        isLiked: viewModel.brandUserState?.isLiked ?? false,
                        isMutatingLike: viewModel.isMutatingLike,
                        brandImageCache: brandImageCache,
                        maxBytes: maxBytes,
                        onLikeTap: {
                            await viewModel.toggleBrandLike(brandID: brand.id)
                        },
                        onShareTap: {
                            activeShareTarget = .brand(brand)
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(OutPickTheme.SwiftUIColor.backgroundBase)

                    BrandDetailSeasonsGridView(
                        seasons: viewModel.seasons,
                        isLoading: viewModel.isLoading,
                        errorMessage: viewModel.errorMessage,
                        canManageBrand: brandAdminSessionStore.canWrite(brandID: brand.id),
                        brandImageCache: brandImageCache,
                        maxBytes: maxBytes,
                        coordinator: coordinator,
                        onSeasonAppear: { season in
                            viewModel.seasonDidAppear(seasonID: season.id)
                        }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(OutPickTheme.SwiftUIColor.backgroundBase)
                }
                .listStyle(.plain)
                .background(OutPickTheme.SwiftUIColor.backgroundBase)
            }
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
        .lookbookNavigationBar(
            title: "",
            showsBackButton: true,
            onBack: { coordinator.pop() }
        ) {
            if brandAdminSessionStore.canWrite(brandID: brand.id) {
                LookbookNavigationTextButton(
                    title: "관리자",
                    accessibilityLabel: "브랜드 관리자"
                ) {
                    coordinator.pushAdminBrandManagement(initialBrandID: brand.id)
                }
            }
        }
        .sheet(item: $activeShareTarget) { target in
            shareSheetFactory(target) { completion in
                activeShareTarget = nil
                shareCompletion = completion
            }
            .applyShareSheetPresentation()
        }
        .sheet(item: $shareCompletion) { completion in
            LookbookShareConfirmationBar(
                roomName: completion.roomName,
                onMove: {
                    moveToSharedChatRoom(completion)
                },
                onClose: {
                    self.shareCompletion = nil
                }
            )
            .applyShareConfirmationSheetPresentation()
        }
        .task {
            await brandAdminSessionStore.ensureWritableBrandsLoaded()

            if didPrepareInitialContent == false {
                await prewarmHeaderLogoIfNeeded()
                await viewModel.prepareBrandInteractionIfNeeded(brand: brand)
                await viewModel.loadContentsIfNeeded(brandID: brand.id)
                didPrepareInitialContent = true
            }
        }
        .appToast(message: viewModel.engagementErrorMessage) {
            viewModel.clearEngagementError()
        }
        .appToast(message: shareMoveErrorMessage) {
            shareMoveErrorMessage = nil
        }
    }

    private func moveToSharedChatRoom(_ completion: LookbookChatShareViewModel.Completion) {
        Task {
            do {
                try await onShareMove(completion)
                shareCompletion = nil
            } catch {
                shareMoveErrorMessage = "채팅방으로 이동할 수 없습니다."
            }
        }
    }

    private var shouldBlockInitialLoading: Bool {
        didPrepareInitialContent == false && viewModel.seasons.isEmpty && viewModel.errorMessage == nil
    }

    private var initialLoadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)
                .scaleEffect(1.05)

            Text("브랜드를 준비하는 중입니다.")
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            OutPickTheme.SwiftUIColor.backgroundBase
                .ignoresSafeArea()
        )
    }

    private var headerPrewarmPath: String? {
        if let thumb = brand.logoThumbPath, thumb.isEmpty == false {
            return thumb
        }

        if let detail = brand.logoDetailPath, detail.isEmpty == false {
            return detail
        }

        if let original = brand.logoOriginalPath, original.isEmpty == false {
            return original
        }

        return nil
    }

    private func prewarmHeaderLogoIfNeeded() async {
        guard let headerPrewarmPath else { return }

        await brandImageCache.prefetch(
            items: [(path: headerPrewarmPath, maxBytes: max(maxBytes, 8_000_000))],
            concurrency: 1,
            storePolicy: .memoryOnly
        )
    }

}
