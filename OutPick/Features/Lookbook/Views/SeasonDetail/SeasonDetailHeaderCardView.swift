//
//  SeasonDetailHeaderCardView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct SeasonDetailHeaderCardView: View {
    let season: Season
    let isLiked: Bool
    let isMutatingLike: Bool
    let onLikeTap: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Text(season.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    Task {
                        await onLikeTap()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isMutatingLike {
                            ProgressView()
                                .controlSize(.small)
                                .tint(isLiked ? .red : .secondary)
                        } else {
                            Image(systemName: isLiked ? "heart.fill" : "heart")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isLiked ? .red : .secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(
                        Capsule()
                            .fill(isLiked ? Color.red.opacity(0.08) : Color(.tertiarySystemFill))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isMutatingLike)
                .accessibilityLabel(isLiked ? "시즌 좋아요 취소 \(season.likeCount)" : "시즌 좋아요 \(season.likeCount)")
            }

            HStack(spacing: 10) {
                Label("\(season.postCount) looks", systemImage: "square.grid.2x2")
                Label("\(season.likeCount) 좋아요", systemImage: isLiked ? "heart.fill" : "heart")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)

            if let description = seasonDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
    }

    private var seasonDescription: String? {
        let trimmed = season.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
