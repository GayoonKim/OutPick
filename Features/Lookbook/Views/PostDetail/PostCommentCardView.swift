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
    let author: CommentAuthorDisplay
    let badges: [PostCommentBadge]
    let avatarImageManager: ChatAvatarImageManaging
    let onProfileTap: (() -> Void)?
    let onRepliesTap: (() -> Void)?
    let onCardTap: (() -> Void)?

    init(
        comment: Comment,
        author: CommentAuthorDisplay? = nil,
        badge: PostCommentBadge? = nil,
        badges: [PostCommentBadge] = [],
        badgeTitle: String? = nil,
        avatarImageManager: ChatAvatarImageManaging = AvatarImageService.shared,
        onProfileTap: (() -> Void)? = nil,
        onRepliesTap: (() -> Void)? = nil,
        onCardTap: (() -> Void)? = nil
    ) {
        self.comment = comment
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
        self.onProfileTap = onProfileTap
        self.onRepliesTap = onRepliesTap
        self.onCardTap = onCardTap
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                onProfileTap?()
            } label: {
                PostCommentAvatarView(
                    avatarPath: author.avatarPath,
                    avatarImageManager: avatarImageManager
                )
            }
            .buttonStyle(.plain)
            .disabled(onProfileTap == nil)
            .accessibilityLabel("\(author.nickname) 프로필 보기")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    HStack(spacing: 6) {
                        Text(author.nickname)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        ForEach(badges, id: \.title) { badge in
                            badgeView(badge)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(dateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(comment.message)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Label("\(comment.likeCount)", systemImage: "heart")

                    if canOpenReplies {
                        Button {
                            onRepliesTap?()
                        } label: {
                            Label("\(comment.replyCount)", systemImage: "bubble.right")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("답글 \(comment.replyCount)개 보기")
                    } else {
                        Label("\(comment.replyCount)", systemImage: "bubble.right")
                    }

                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            onCardTap?()
        }
    }

    @ViewBuilder
    private func badgeView(_ badge: PostCommentBadge) -> some View {
        if let systemImage = badge.systemImage {
            Image(systemName: systemImage)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.black)
                .clipShape(Circle())
                .accessibilityLabel(badge.title)
        } else {
            Text(badge.title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black)
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
        comment.replyCount > 0 && onRepliesTap != nil
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
                .fill(Color(.tertiarySystemFill))
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
