//
//  CreateBrandFinishingView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct CreateBrandFinishingView: View {
    let createdBrand: CreateBrandViewModel.CreatedBrand

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 12) {
                Text("브랜드 생성을 마무리하고 있습니다")
                    .font(.system(size: 28, weight: .bold, design: .rounded))

                Text("\(createdBrand.name) 브랜드 문서는 이미 생성되었습니다. 로고 이미지를 홈 목록에서 자연스럽게 보여주기 위해 최소 썸네일 리소스를 준비하고 있습니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 14) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.black)

                Text("브랜드 로고 썸네일을 준비 중입니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(red: 0.98, green: 0.97, blue: 0.94).ignoresSafeArea())
    }
}
