//
//  BrandDetailView.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/26.
//

import SwiftUI

/// 브랜드 상세: 현재는 헤더(로고/이름/좋아요/분리선)만 보여줍니다.
struct BrandDetailView: View {
    let brand: Brand
    let imageLoader: any ImageLoading

    /// ViewModel의 thumbMaxBytes와 동일 값으로 맞추는 게 가장 좋습니다.
    /// - 지금은 기본값을 두되, 필요하면 호출부에서 주입하세요.
    let maxBytes: Int

    init(
        brand: Brand,
        imageLoader: any ImageLoading,
        maxBytes: Int = 1_000_000
    ) {
        self.brand = brand
        self.imageLoader = imageLoader
        self.maxBytes = maxBytes
    }

    var body: some View {
        List {
            BrandDetailHeaderView(
                brand: brand,
                imageLoader: imageLoader,
                maxBytes: maxBytes
            )
            .listRowInsets(EdgeInsets())   // 이미지가 좌우 끝까지 붙게
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle(brand.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
