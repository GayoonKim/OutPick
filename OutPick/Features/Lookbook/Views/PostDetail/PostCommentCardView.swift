//
//  PostCommentCardView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI
import UIKit

struct PostCommentBadge: Equatable {
    let title: String
    let systemImage: String?

    static let pinned = PostCommentBadge(title: "고정", systemImage: "pin.fill")
    static let representative = PostCommentBadge(title: "대표", systemImage: "hand.thumbsup.fill")
}

struct PostCommentCardView: View {
    let comment: Comment
    let likeCount: Int
    let replyCount: Int
    let isLiked: Bool
    let isMutatingLike: Bool
    let author: CommentAuthorDisplay
    let badges: [PostCommentBadge]
    let avatarImageManager: ChatAvatarImageManaging
    let actions: PostCommentCardActions

    init(
        comment: Comment,
        likeCount: Int? = nil,
        replyCount: Int? = nil,
        isLiked: Bool = false,
        isMutatingLike: Bool = false,
        author: CommentAuthorDisplay? = nil,
        badge: PostCommentBadge? = nil,
        badges: [PostCommentBadge] = [],
        badgeTitle: String? = nil,
        avatarImageManager: ChatAvatarImageManaging,
        actions: PostCommentCardActions = PostCommentCardActions()
    ) {
        self.comment = comment
        self.likeCount = likeCount ?? comment.likeCount
        self.replyCount = replyCount ?? comment.replyCount
        self.isLiked = isLiked
        self.isMutatingLike = isMutatingLike
        self.author = author ?? .unknown(userID: comment.userID)
        if badges.isEmpty == false {
            self.badges = badges
        } else if let badge {
            self.badges = [badge]
        } else if let badgeTitle {
            self.badges = [PostCommentBadge(title: badgeTitle, systemImage: nil)]
        } else {
            self.badges = []
        }
        self.avatarImageManager = avatarImageManager
        self.actions = actions
    }

    var body: some View {
        cardContent
            .contextMenu {
                if let onDeleteTap = actions.onDeleteTap {
                    Button(role: .destructive) {
                        onDeleteTap()
                    } label: {
                        Label("삭제", systemImage: "trash")
                    }
                    .accessibilityIdentifier("lookbook.comment.deleteAction")
                }

                if let onReportTap = actions.onReportTap {
                    Button(role: .destructive) {
                        onReportTap()
                    } label: {
                        Label("신고", systemImage: "exclamationmark.bubble")
                    }
                    .accessibilityIdentifier("lookbook.comment.reportAction")
                }

                if let onBlockTap = actions.onBlockTap {
                    Button(role: .destructive) {
                        onBlockTap()
                    } label: {
                        Label("차단", systemImage: "person.crop.circle.badge.xmark")
                    }
                    .accessibilityIdentifier("lookbook.comment.blockAction")
                }
            }
    }

    private var cardContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                actions.onProfileTap?()
            } label: {
                PostCommentAvatarView(
                    avatarPath: author.avatarPath,
                    avatarImageManager: avatarImageManager
                )
            }
            .buttonStyle(.plain)
            .disabled(actions.onProfileTap == nil)
            .accessibilityLabel("\(author.nickname) 프로필 보기")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(author.nickname)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                            .lineLimit(1)

                        ForEach(badges, id: \.title) { badge in
                            badgeView(badge)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(dateText)
                        .font(.caption)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .lineLimit(1)
                }

                Text(comment.message)
                    .font(.subheadline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    likeControl

                    if canOpenReplies {
                        Button {
                            actions.onRepliesTap?()
                        } label: {
                            Label("\(replyCount)", systemImage: "bubble.right")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("답글 \(replyCount)개 보기 및 작성")
                        .accessibilityIdentifier("lookbook.comment.repliesButton")
                    } else {
                        Label("\(replyCount)", systemImage: "bubble.right")
                    }

                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .monospacedDigit()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            actions.onCardTap?()
        }
        .accessibilityIdentifier("lookbook.comment.card")
    }

    @ViewBuilder
    private var likeControl: some View {
        if let onLikeTap = actions.onLikeTap {
            Button {
                Task {
                    await onLikeTap()
                }
            } label: {
                Label("\(likeCount)", systemImage: isLiked ? "heart.fill" : "heart")
            }
            .buttonStyle(.plain)
            .disabled(isMutatingLike)
            .foregroundStyle(
                isLiked
                    ? OutPickTheme.SwiftUIColor.like
                    : OutPickTheme.SwiftUIColor.iconSecondary
            )
            .accessibilityLabel(isLiked ? "댓글 좋아요 취소" : "댓글 좋아요")
            .accessibilityIdentifier("lookbook.comment.likeButton")
        } else {
            Label("\(likeCount)", systemImage: "heart")
        }
    }

    @ViewBuilder
    private func badgeView(_ badge: PostCommentBadge) -> some View {
        if let systemImage = badge.systemImage {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                .frame(width: 20, height: 20)
                .background(OutPickTheme.SwiftUIColor.accent)
                .clipShape(Circle())
                .accessibilityLabel(badge.title)
        } else {
            Text(badge.title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(OutPickTheme.SwiftUIColor.accent)
                .clipShape(Capsule())
        }
    }

    private var dateText: String {
        relativeDateText(from: comment.createdAt, to: Date())
    }

    private func relativeDateText(from date: Date, to now: Date) -> String {
        let seconds = max(Int(now.timeIntervalSince(date)), 0)
        let minute = 60
        let hour = minute * 60
        let day = hour * 24
        let week = day * 7
        let month = day * 30
        let year = day * 365

        switch seconds {
        case ..<minute:
            return "방금 전"
        case ..<hour:
            return "\(seconds / minute)분 전"
        case ..<day:
            return "\(seconds / hour)시간 전"
        case ..<week:
            return "\(seconds / day)일 전"
        case ..<(week * 5):
            return "\(seconds / week)주 전"
        case ..<year:
            return "\(seconds / month)개월 전"
        default:
            return "\(seconds / year)년 전"
        }
    }

    private var canOpenReplies: Bool {
        actions.onRepliesTap != nil
    }
}

private struct PostCommentAvatarView: View {
    let avatarPath: String?
    let avatarImageManager: ChatAvatarImageManaging

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
        .frame(width: 34, height: 34)
        .clipShape(Circle())
        .background(
            Circle()
                .fill(OutPickTheme.SwiftUIColor.surfaceElevated)
        )
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
