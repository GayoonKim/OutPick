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

                Text(descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let websiteURL = createdBrand.websiteURL, websiteURL.isEmpty == false {
                Label("공식 홈페이지: \(websiteURL)", systemImage: "link")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let lookbookArchiveURL = createdBrand.lookbookArchiveURL,
               lookbookArchiveURL.isEmpty == false {
                Label("룩북 목록: \(lookbookArchiveURL)", systemImage: "photo.on.rectangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
                .foregroundStyle(.white)
                .background(Color.black)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea())
    }
}
