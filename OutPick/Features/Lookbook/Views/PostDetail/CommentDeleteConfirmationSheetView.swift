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
    let avatarImageManager: AvatarImageManaging
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                CommentSafetyAvatarView(
                    avatarPath: author.avatarPath,
                    size: 52,
                    avatarImageManager: avatarImageManager
                )

                VStack(spacing: 4) {
                    Text("댓글을 삭제할까요?")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("삭제한 댓글은 다시 복구할 수 없습니다.")
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .layoutPriority(1)
            }
            .padding(.top, 22)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(role: .destructive) {
                    onConfirm()
                } label: {
                    HStack {
                        if isDeleting {
                            ProgressView()
                                .tint(OutPickTheme.SwiftUIColor.backgroundBase)
                        }
                        Text("삭제하기")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(OutPickTheme.SwiftUIColor.destructive)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
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
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .background(OutPickTheme.SwiftUIColor.surfaceBase)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
    }
}
