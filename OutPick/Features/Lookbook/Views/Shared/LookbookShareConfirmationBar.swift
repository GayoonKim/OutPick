//
//  LookbookShareConfirmationBar.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import SwiftUI

struct LookbookShareConfirmationBar: View {
    let roomName: String
    let onMove: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("채팅방에 공유했어요")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                Text(roomName)
                    .font(.subheadline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .lineLimit(1)
            }

            VStack(spacing: 10) {
                Button(action: onMove) {
                    Text("채팅방으로 이동")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(OutPickTheme.SwiftUIColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button("계속 보기", action: onClose)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .frame(height: 34)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity)
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
    }
}
