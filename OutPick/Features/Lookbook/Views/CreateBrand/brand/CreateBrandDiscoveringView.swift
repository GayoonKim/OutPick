//
//  CreateBrandDiscoveringView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct CreateBrandDiscoveringView: View {
    let createdBrand: CreateBrandViewModel.CreatedBrand
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("등록할 시즌을 찾고 있습니다")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("\(createdBrand.name) 브랜드를 만들었습니다. 이제 가져올 수 있는 시즌을 찾고 있습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let lookbookArchiveURL = createdBrand.lookbookArchiveURL,
                   !lookbookArchiveURL.isEmpty {
                    Label(lookbookArchiveURL, systemImage: "photo.on.rectangle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("룩북 주소가 없어도 브랜드는 그대로 저장됩니다.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.black)

                Text("잠시만 기다려주세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)

            Button {
                onSkip()
            } label: {
                HStack {
                    Spacer()
                    Text("바로 확인하기")
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
