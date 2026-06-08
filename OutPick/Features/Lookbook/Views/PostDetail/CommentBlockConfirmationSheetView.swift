//
//  CommentBlockConfirmationSheetView.swift
//  OutPick
//
//  Created by Codex on 5/11/26.
//

import SwiftUI

struct CommentBlockConfirmationSheetView: View {
    let author: CommentAuthorDisplay
    let isBlocking: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(OutPickTheme.SwiftUIColor.borderSubtle)
                .frame(width: 38, height: 5)
                .padding(.top, 6)

            VStack(spacing: 10) {
                CommentSafetyAvatarView(avatarPath: author.avatarPath, size: 52)

                Text("\(author.nickname)님을 차단할까요?")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("차단하면 서로의 댓글, 답글, 프로필 활동이 앱에서 보이지 않습니다.", systemImage: "eye.slash")
                Label("상대방에게 차단 사실을 알리지 않습니다.", systemImage: "bell.slash")
                Label("설정에서 언제든지 차단을 해제할 수 있습니다.", systemImage: "gearshape")
            }
            .font(.footnote)
            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(role: .destructive) {
                    onConfirm()
                } label: {
                    HStack {
                        if isBlocking {
                            ProgressView()
                                .tint(OutPickTheme.SwiftUIColor.backgroundBase)
                        }
                        Text("차단하기")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(OutPickTheme.SwiftUIColor.destructive)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isBlocking)
                .accessibilityIdentifier("lookbook.comment.blockConfirmButton")

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
                .disabled(isBlocking)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
    }
}
