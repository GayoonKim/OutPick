//
//  CreateBrandCompletedView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct CreateBrandCompletedView: View {
    let createdBrand: CreateBrandViewModel.CreatedBrand
    let onComplete: () -> Void

    private var descriptionText: String {
        if createdBrand.canDiscoverSeasons {
            return "브랜드를 만들었습니다. 이어서 시즌을 추가할 수 있습니다."
        }
        if createdBrand.hasLogoAsset {
            return "브랜드를 만들었고, 로고 준비도 끝났습니다."
        }
        return "브랜드를 만들었습니다."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("브랜드 생성이 완료되었습니다")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                Text(descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let websiteURL = createdBrand.websiteURL, websiteURL.isEmpty == false {
                Label("공식 홈페이지: \(websiteURL)", systemImage: "link")
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            if let lookbookArchiveURL = createdBrand.lookbookArchiveURL,
               lookbookArchiveURL.isEmpty == false {
                Label("룩북 목록: \(lookbookArchiveURL)", systemImage: "photo.on.rectangle")
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            Button {
                onComplete()
            } label: {
                HStack {
                    Spacer()
                    Text("확인")
                        .font(.headline)
                    Spacer()
                }
                .padding(.vertical, 16)
                .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                .background(OutPickTheme.SwiftUIColor.accent)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
    }
}
