//
//  LookbookShareUnavailableView.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import SwiftUI

struct LookbookShareUnavailableView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 12) {
            Text("공유를 준비하지 못했어요")
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            Text("잠시 후 다시 시도해주세요.")
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

            Button("닫기") {
                dismiss()
            }
            .font(.footnote.weight(.bold))
            .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
    }
}
