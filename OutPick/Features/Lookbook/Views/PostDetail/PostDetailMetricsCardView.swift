//
//  PostDetailMetricsCardView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct PostDetailMetricsCardView: View {
    let post: LookbookPost
    let commentCount: Int
    let isLiked: Bool
    let isMutatingLike: Bool
    let onLikeTap: () async -> Void
    let onCommentTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            actionButton(
                systemName: "heart",
                selectedSystemName: "heart.fill",
                value: post.metrics.likeCount,
                title: "좋아요",
                isSelected: isLiked,
                isMutating: isMutatingLike,
                selectedColor: OutPickTheme.SwiftUIColor.like,
                action: onLikeTap
            )
            .accessibilityIdentifier("lookbook.post.likeButton")
            actionButton(
                systemName: "message",
                selectedSystemName: "message.fill",
                value: commentCount,
                title: "댓글",
                isSelected: false,
                isMutating: false,
                selectedColor: OutPickTheme.SwiftUIColor.iconSecondary,
                action: {
                    onCommentTap()
                }
            )
            .accessibilityIdentifier("lookbook.post.commentsButton")
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func actionButton(
        systemName: String,
        selectedSystemName: String,
        value: Int,
        title: String,
        isSelected: Bool,
        isMutating: Bool,
        selectedColor: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task {
                await action()
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Image(systemName: isSelected ? selectedSystemName : systemName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(isSelected ? selectedColor : OutPickTheme.SwiftUIColor.iconSecondary)
                        .opacity(isMutating ? 0 : 1)

                    if isMutating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(isSelected ? selectedColor : OutPickTheme.SwiftUIColor.iconSecondary)
                    }
                }
                .frame(height: 22)

                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

                Text("\(value)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 76)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? selectedColor.opacity(0.12)
                            : OutPickTheme.SwiftUIColor.surfaceElevated
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) \(value)")
    }
}
