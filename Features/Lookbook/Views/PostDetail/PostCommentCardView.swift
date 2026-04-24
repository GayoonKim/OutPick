//
//  PostCommentCardView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct PostCommentCardView: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(comment.userID.value)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(comment.isDeleted ? "삭제된 댓글입니다." : comment.message)
                .font(.subheadline)
                .foregroundStyle(comment.isDeleted ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)
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
}
