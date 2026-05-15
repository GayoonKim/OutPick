//
//  CommentDeleteConfirmationSheetView.swift
//  OutPick
//
//  Created by Codex on 5/15/26.
//

import SwiftUI

struct CommentDeleteConfirmationSheetView: View {
    let author: CommentAuthorDisplay
    let isDeleting: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            VStack(spacing: 12) {
                CommentSafetyAvatarView(avatarPath: author.avatarPath, size: 64)

                VStack(spacing: 4) {
                    Text("댓글을 삭제할까요?")
                        .font(.headline.weight(.bold))
                        .multilineTextAlignment(.center)

                    Text("삭제한 댓글은 다시 복구할 수 없습니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(role: .destructive) {
                    onConfirm()
                } label: {
                    HStack {
                        if isDeleting {
                            ProgressView()
                                .tint(.white)
                        }
                        Text("삭제하기")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
                .accessibilityIdentifier("lookbook.comment.deleteConfirmButton")

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
                .disabled(isDeleting)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background(Color.white.ignoresSafeArea())
    }
}
