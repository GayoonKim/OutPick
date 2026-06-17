//
//  SeasonDetailView.swift
//  OutPick
//
//  Created by Codex on 2/21/26.
//

import SwiftUI

struct SeasonDetailView: View {
    let brandID: BrandID
    let seasonID: SeasonID

    private let brandImageCache: any BrandImageCacheProtocol
    private let coordinator: LookbookCoordinator
    private let shareSheetFactory: (LookbookShareTarget, @escaping (LookbookChatShareViewModel.Completion) -> Void) -> AnyView
    private let onShareMove: (LookbookChatShareViewModel.Completion) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SeasonDetailViewModel
    @State private var selectedPost: LookbookPost?
    @State private var activeShareTarget: LookbookShareTarget?
    @State private var shareCompletion: LookbookChatShareViewModel.Completion?
    @State private var shareMoveErrorMessage: String?

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]
    init(
        brandID: BrandID,
        seasonID: SeasonID,
        viewModel: SeasonDetailViewModel,
        brandImageCache: any BrandImageCacheProtocol,
        coordinator: LookbookCoordinator,
        shareSheetFactory: @escaping (LookbookShareTarget, @escaping (LookbookChatShareViewModel.Completion) -> Void) -> AnyView,
        onShareMove: @escaping (LookbookChatShareViewModel.Completion) async throws -> Void
    ) {
        self.brandID = brandID
        self.seasonID = seasonID
        self.brandImageCache = brandImageCache
        self.coordinator = coordinator
        self.shareSheetFactory = shareSheetFactory
        self.onShareMove = onShareMove
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            if shouldBlockInitialLoading {
                loadingSection
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        if let season = viewModel.season {
                            SeasonDetailHeaderCardView(
                                season: season,
                                isLiked: viewModel.seasonUserState?.isLiked ?? false,
                                isMutatingLike: viewModel.isMutatingLike,
                                onLikeTap: {
                                    await viewModel.toggleSeasonLike()
                                },
                                onShareTap: {
                                    activeShareTarget = .season(season)
                                }
                            )
                        }

                        if let errorMessage = viewModel.errorMessage, viewModel.posts.isEmpty {
                            errorSection(message: errorMessage)
                        } else if viewModel.posts.isEmpty {
                            emptySection
                        } else {
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(viewModel.posts, id: \.id) { post in
                                    Button {
                                        selectedPost = post
                                    } label: {
                                        SeasonLookGridItemView(
                                            post: post,
                                            commentCount: viewModel.displayCommentCount(for: post),
                                            brandImageCache: brandImageCache
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("lookbook.post.card")
                                    .onAppear {
                                        viewModel.postDidAppear(postID: post.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .lookbookNavigationBar(
            title: "",
            showsBackButton: true,
            onBack: { dismiss() }
        )
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
        .background(hiddenNavigationLink)
        .task {
            await viewModel.loadIfNeeded()
        }
        .refreshable {
            await viewModel.refresh()
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

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)
            Text("포스트 목록을 불러오는 중입니다.")
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorSection(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("룩북을 불러오지 못했습니다.")
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var emptySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("등록된 룩이 없습니다.")
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            Text("아직 이 시즌에 준비된 사진이 없습니다.")
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var hiddenNavigationLink: some View {
        NavigationLink(
            destination: selectedPostDestination,
            isActive: selectedPostBinding
        ) {
            EmptyView()
        }
        .hidden()
    }

    @ViewBuilder
    private var selectedPostDestination: some View {
        if let selectedPost {
            coordinator.makePostDetailView(post: selectedPost)
        } else {
            EmptyView()
        }
    }

    private var selectedPostBinding: Binding<Bool> {
        Binding(
            get: { selectedPost != nil },
            set: { isActive in
                if !isActive {
                    selectedPost = nil
                }
            }
        )
    }

    private var shouldBlockInitialLoading: Bool {
        viewModel.isLoading && viewModel.posts.isEmpty && viewModel.errorMessage == nil
    }
}
