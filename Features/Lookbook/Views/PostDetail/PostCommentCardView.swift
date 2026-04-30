//
//  PostCommentCardView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct PostCommentCardView: View {
    let comment: Comment
    let badgeTitle: String?
    let onRepliesTap: (() -> Void)?

    init(
        comment: Comment,
        badgeTitle: String? = nil,
        onRepliesTap: (() -> Void)? = nil
    ) {
        self.comment = comment
        self.badgeTitle = badgeTitle
        self.onRepliesTap = onRepliesTap
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Text(comment.userID.value)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let badgeTitle {
                        Text(badgeTitle)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.black)
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(comment.isDeleted ? "삭제된 댓글입니다." : comment.message)
                .font(.subheadline)
                .foregroundStyle(comment.isDeleted ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            if comment.isDeleted == false {
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

                    if comment.attachments.isEmpty == false {
                        Label("\(comment.attachments.count)", systemImage: "paperclip")
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
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일"
        return formatter.string(from: comment.createdAt)
    }

    private var canOpenReplies: Bool {
        comment.replyCount > 0 && onRepliesTap != nil
    }
}
