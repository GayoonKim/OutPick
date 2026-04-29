//
//  PostDetailMetricsCardView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct PostDetailMetricsCardView: View {
    let post: LookbookPost
    let isLiked: Bool
    let isSaved: Bool
    let errorMessage: String?
    let onLikeTap: () -> Void
    let onCommentTap: () -> Void
    let onSaveTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                actionButton(
                    systemName: "heart",
                    selectedSystemName: "heart.fill",
                    value: post.metrics.likeCount,
                    title: "좋아요",
                    isSelected: isLiked,
                    selectedColor: .red,
                    action: onLikeTap
                )
                actionButton(
                    systemName: "message",
                    selectedSystemName: "message.fill",
                    value: post.metrics.commentCount,
                    title: "댓글",
                    isSelected: false,
                    selectedColor: .black,
                    action: onCommentTap
                )
                actionButton(
                    systemName: "bookmark",
                    selectedSystemName: "bookmark.fill",
                    value: post.metrics.saveCount,
                    title: "저장",
                    isSelected: isSaved,
                    selectedColor: .black,
                    action: onSaveTap
                )
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func actionButton(
        systemName: String,
        selectedSystemName: String,
        value: Int,
        title: String,
        isSelected: Bool,
        selectedColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: isSelected ? selectedSystemName : systemName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(isSelected ? selectedColor : .secondary)
                    .frame(height: 22)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("\(value)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? selectedColor.opacity(0.08) : Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(value)")
    }
}
