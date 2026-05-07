//
//  PostCommentsSheetView.swift
//  OutPick
//
//  Created by Codex on 5/1/26.
//

import SwiftUI
import UIKit

struct PostCommentsSheetView: View {
    @StateObject private var viewModel: PostCommentsViewModel
    private let navigationCoordinator: LookbookCoordinator
    private let brandID: BrandID
    private let seasonID: SeasonID
    private let postID: PostID
    @ObservedObject private var coordinator: PostCommentCoordinator
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @State private var pendingDeleteItem: CommentDisplayItem?
    @State private var pendingReportItem: CommentDisplayItem?
    @State private var pendingBlockItem: CommentDisplayItem?
    @State private var isConfirmingDelete: Bool = false
    @State private var isSelectingReportReason: Bool = false
    @State private var isPresentingBlockSheet: Bool = false
    private let onCommentSubmitted: (CommentMutationResult) -> Void
    private let onCommentDeleted: (CommentDeletionResult) -> Void

    init(
        viewModel: PostCommentsViewModel,
        navigationCoordinator: LookbookCoordinator,
        brandID: BrandID,
        seasonID: SeasonID,
        postID: PostID,
        coordinator: PostCommentCoordinator,
        onCommentSubmitted: @escaping (CommentMutationResult) -> Void = { _ in },
        onCommentDeleted: @escaping (CommentDeletionResult) -> Void = { _ in }
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.navigationCoordinator = navigationCoordinator
        self.brandID = brandID
        self.seasonID = seasonID
        self.postID = postID
        self.coordinator = coordinator
        self.onCommentSubmitted = onCommentSubmitted
        self.onCommentDeleted = onCommentDeleted
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView(showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if shouldShowInitialLoading {
                        loadingSection
                    } else {
                        commentsContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .refreshable {
                await viewModel.refresh()
            }
        }
        .background(Color(red: 0.98, green: 0.97, blue: 0.95).ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            inputBar
        }
        .sheet(isPresented: replySheetBinding) {
            repliesSheet
        }
        .sheet(isPresented: profileSheetBinding) {
            profileSheet
        }
        .task {
            await viewModel.loadIfNeeded()
            await brandAdminSessionStore.refreshWritableBrands()
        }
        .confirmationDialog(
            "댓글을 삭제할까요?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("삭제", role: .destructive) {
                guard let pendingDeleteItem else { return }
                Task {
                    if let result = await viewModel.deleteComment(pendingDeleteItem.comment) {
                        onCommentDeleted(result)
                    }
                    self.pendingDeleteItem = nil
                }
            }
            Button("취소", role: .cancel) {
                pendingDeleteItem = nil
            }
        }
        .confirmationDialog(
            "신고 사유를 선택해주세요.",
            isPresented: $isSelectingReportReason,
            titleVisibility: .visible
        ) {
            ForEach(CommentReportReason.allCases, id: \.self) { reason in
                Button(reason.title, role: .destructive) {
                    guard let pendingReportItem else { return }
                    Task {
                        await viewModel.reportComment(
                            pendingReportItem.comment,
                            author: pendingReportItem.author,
                            reason: reason
                        )
                        self.pendingReportItem = nil
                    }
                }
            }
            Button("취소", role: .cancel) {
                pendingReportItem = nil
            }
        }
        .sheet(isPresented: blockSheetBinding) {
            blockConfirmationSheet
        }
        .alert(
            "작업을 완료하지 못했습니다.",
            isPresented: actionErrorBinding
        ) {
            Button("확인") {
                viewModel.clearActionError()
            }
        } message: {
            Text(viewModel.actionErrorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("댓글")
                .font(.headline.weight(.bold))

            Spacer()

            sortControl

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("댓글 닫기")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
    }

    @ViewBuilder
    private var commentsContent: some View {
        if shouldShowEmptyState {
            emptyStateSection
        } else {
            ForEach(commentFeedItems) { item in
                commentCard(item.displayItem, badges: item.badges)
                    .onAppear {
                        viewModel.prefetchAuthorAvatars(around: item.id)
                        guard item.displayItem.comment.id == viewModel.rootComments.last?.id else { return }
                        Task {
                            await viewModel.loadNextPage()
                        }
                    }
            }

            if viewModel.isLoadingMore {
                ProgressView()
                    .tint(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
        }
    }

    private func commentCard(
        _ item: CommentDisplayItem,
        badges: [PostCommentBadge] = []
    ) -> some View {
        PostCommentCardView(
            comment: item.comment,
            author: item.author,
            badges: badges,
            onProfileTap: {
                coordinator.presentProfile(for: item.author)
            },
            onRepliesTap: {
                coordinator.presentReplies(for: item.comment)
            },
            onDeleteTap: deleteAction(for: item),
            onReportTap: reportAction(for: item),
            onBlockTap: blockAction(for: item)
        )
    }

    private func deleteAction(for item: CommentDisplayItem) -> (() -> Void)? {
        guard viewModel.canDelete(
            item.comment,
            isBrandWritable: brandAdminSessionStore.canWrite(brandID: brandID)
        ) else {
            return nil
        }

        return {
            pendingDeleteItem = item
            isConfirmingDelete = true
        }
    }

    private func reportAction(for item: CommentDisplayItem) -> (() -> Void)? {
        guard viewModel.canReportOrBlock(item.comment) else { return nil }

        return {
            pendingReportItem = item
            isSelectingReportReason = true
        }
    }

    private func blockAction(for item: CommentDisplayItem) -> (() -> Void)? {
        guard viewModel.canReportOrBlock(item.comment) else { return nil }

        return {
            pendingBlockItem = item
            isPresentingBlockSheet = true
        }
    }

    private var blockSheetBinding: Binding<Bool> {
        Binding(
            get: { isPresentingBlockSheet && pendingBlockItem != nil },
            set: { isPresented in
                isPresentingBlockSheet = isPresented
                if isPresented == false {
                    pendingBlockItem = nil
                }
            }
        )
    }

    @ViewBuilder
    private var blockConfirmationSheet: some View {
        if let pendingBlockItem {
            let sheet = CommentBlockConfirmationSheetView(
                author: pendingBlockItem.author,
                isBlocking: viewModel.isPerformingCommentAction,
                onCancel: {
                    isPresentingBlockSheet = false
                    self.pendingBlockItem = nil
                },
                onConfirm: {
                    Task {
                        await viewModel.blockAuthor(
                            of: pendingBlockItem.comment,
                            author: pendingBlockItem.author
                        )
                        isPresentingBlockSheet = false
                        self.pendingBlockItem = nil
                    }
                }
            )
            if #available(iOS 16.0, *) {
                sheet
                    .presentationDetents([.height(360)])
                    .presentationDragIndicator(.visible)
            } else {
                sheet
            }
        } else {
            EmptyView()
        }
    }

    private var actionErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.actionErrorMessage != nil },
            set: { isPresented in
                if isPresented == false {
                    viewModel.clearActionError()
                }
            }
        )
    }

    private var replySheetBinding: Binding<Bool> {
        Binding(
            get: { coordinator.replyRoute != nil },
            set: { isPresented in
                if isPresented == false {
                    coordinator.dismissReplies()
                }
            }
        )
    }

    private var profileSheetBinding: Binding<Bool> {
        Binding(
            get: { coordinator.profileRoute != nil },
            set: { isPresented in
                if isPresented == false {
                    coordinator.dismissProfile()
                }
            }
        )
    }

    @ViewBuilder
    private var repliesSheet: some View {
        if let route = coordinator.replyRoute {
            let sheet = navigationCoordinator.makeRepliesSheet(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID,
                parentComment: route.parentComment,
                onReplySubmitted: onCommentSubmitted,
                onCommentDeleted: onCommentDeleted
            )
            if #available(iOS 16.0, *) {
                sheet
                    .presentationDetents([.fraction(0.62)])
                    .presentationDragIndicator(.visible)
            } else {
                sheet
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private var profileSheet: some View {
        if let route = coordinator.profileRoute {
            CommentUserProfileDetailView(
                author: route.author,
                onBack: {
                    coordinator.dismissProfile()
                }
            )
        } else {
            EmptyView()
        }
    }

    private var inputBar: some View {
        PostCommentInputBarView(
            text: $viewModel.draftMessage,
            placeholder: "댓글을 입력하세요.",
            isSubmitting: viewModel.isSubmittingComment,
            canSubmit: viewModel.canSubmitComment,
            errorMessage: viewModel.submissionErrorMessage,
            onSubmit: {
                if let result = await viewModel.submitComment() {
                    onCommentSubmitted(result)
                }
            }
        )
    }

    private var sortControl: some View {
        HStack(spacing: 6) {
            sortButton(.latest)
            sortButton(.popular)
        }
        .padding(4)
        .background(Color(.tertiarySystemFill))
        .clipShape(Capsule())
    }

    private func sortButton(_ sort: CommentSortOption) -> some View {
        Button {
            Task {
                await viewModel.selectSort(sort)
            }
        } label: {
            Text(sort.title)
                .font(.caption.weight(.bold))
                .foregroundStyle(viewModel.selectedSort == sort ? .white : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(viewModel.selectedSort == sort ? Color.black : Color.clear)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("댓글 \(sort.title) 정렬")
    }

    private var loadingSection: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(.black)

            Text("댓글을 불러오는 중입니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var emptyStateSection: some View {
        Text("해당 포스트에 아직 댓글이 없습니다.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
            .multilineTextAlignment(.center)
    }

    private var shouldShowInitialLoading: Bool {
        viewModel.isLoading &&
            viewModel.pinnedComments.isEmpty &&
            viewModel.representativeComment == nil &&
            viewModel.rootComments.isEmpty
    }

    private var shouldShowEmptyState: Bool {
        viewModel.pinnedComments.isEmpty &&
            viewModel.representativeComment == nil &&
            viewModel.rootComments.isEmpty
    }

    private var commentFeedItems: [CommentFeedItem] {
        var items = viewModel.pinnedComments.map {
            CommentFeedItem(displayItem: viewModel.displayItem(for: $0), badges: [.pinned])
        }

        if let representativeComment = viewModel.representativeComment {
            if let pinnedIndex = items.firstIndex(where: { $0.id == representativeComment.id }) {
                items[pinnedIndex].badges.append(.representative)
            } else {
                items.append(
                    CommentFeedItem(
                        displayItem: viewModel.displayItem(for: representativeComment),
                        badges: [.representative]
                    )
                )
            }
        }

        items.append(contentsOf: viewModel.rootComments.map {
            CommentFeedItem(displayItem: viewModel.displayItem(for: $0), badges: [])
        })

        return items
    }
}

private extension CommentSortOption {
    var title: String {
        switch self {
        case .latest:
            return "최신순"
        case .popular:
            return "인기순"
        }
    }
}

private struct CommentFeedItem: Identifiable {
    let displayItem: CommentDisplayItem
    var badges: [PostCommentBadge]

    var id: CommentID {
        displayItem.id
    }
}

struct CommentBlockConfirmationSheetView: View {
    let author: CommentAuthorDisplay
    let isBlocking: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            VStack(spacing: 12) {
                CommentBlockAvatarView(avatarPath: author.avatarPath)

                Text("\(author.nickname)님을 차단할까요?")
                    .font(.headline.weight(.bold))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("차단하면 서로의 댓글, 답글, 프로필 활동이 앱에서 보이지 않습니다.", systemImage: "eye.slash")
                Label("상대방에게 차단 사실을 알리지 않습니다.", systemImage: "bell.slash")
                Label("설정에서 언제든지 차단을 해제할 수 있습니다.", systemImage: "gearshape")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(role: .destructive) {
                    onConfirm()
                } label: {
                    HStack {
                        if isBlocking {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("차단하기")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isBlocking)

                Button {
                    onCancel()
                } label: {
                    Text("취소")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(isBlocking)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background(Color.white.ignoresSafeArea())
    }
}

private struct CommentBlockAvatarView: View {
    let avatarPath: String?
    let avatarImageManager: ChatAvatarImageManaging = AvatarImageService.shared

    @State private var image: UIImage?
    @State private var loadedPath: String?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("Default_Profile")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(Circle())
        .background(Circle().fill(Color(.tertiarySystemFill)))
        .task(id: avatarPath) {
            await loadAvatarIfNeeded()
        }
    }

    private func loadAvatarIfNeeded() async {
        let normalizedPath = avatarPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedPath, normalizedPath.isEmpty == false else {
            image = nil
            loadedPath = nil
            return
        }
        guard loadedPath != normalizedPath else { return }

        loadedPath = normalizedPath
        if let cachedImage = await avatarImageManager.cachedAvatar(for: normalizedPath) {
            image = cachedImage
            return
        }

        image = try? await avatarImageManager.loadAvatar(
            for: normalizedPath,
            maxBytes: 3 * 1024 * 1024
        )
    }
}
