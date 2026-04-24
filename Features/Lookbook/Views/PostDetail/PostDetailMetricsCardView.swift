//
//  PostDetailMetricsCardView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct PostDetailMetricsCardView: View {
    let post: LookbookPost

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 22) {
                metricChip(
                    systemName: "heart",
                    value: post.metrics.likeCount,
                    title: "좋아요"
                )
                metricChip(
                    systemName: "message",
                    value: post.metrics.commentCount,
                    title: "댓글"
                )
                metricChip(
                    systemName: "bookmark",
                    value: post.metrics.saveCount,
                    title: "저장"
                )
            }

            if let viewCount = post.metrics.viewCount {
                Text("조회 \(viewCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func metricChip(
        systemName: String,
        value: Int,
        title: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemName)
                Text(title)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Text("\(value)")
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .monospacedDigit()
        }
    }
}
