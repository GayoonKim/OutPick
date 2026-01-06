//
//  BrandDetailHeaderView.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/26.
//

import SwiftUI

struct BrandDetailHeaderView: View {
    let brand: Brand
    let imageLoader: any ImageLoading
    let maxBytes: Int

    @State private var uiImage: UIImage?
    @State private var loadFailed: Bool = false

    /// ViewModel 프리패치와 cacheKey 규칙을 반드시 동일하게 맞춰야 캐시 히트가 납니다.
    /// - 지금은 이전에 쓰던 규칙을 그대로 사용합니다.
    private var cacheKey: String? {
        guard let path = brand.logoPath, path.isEmpty == false else { return nil }
        return "brandLogoThumb|\(path)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 상단 로고(큰 이미지) - 캐시된 UIImage를 사용
            ZStack {
                if let uiImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        // 좌/우 빈 공간이 생기지 않도록 채우기(필요한 만큼 일부가 잘릴 수 있음)
                        .scaledToFill()
                        // 얼굴이 위쪽에서 잘리는 경우가 많아서 상단 기준으로 크롭되도록 정렬을 고정합니다.
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .clipped()
                } else if loadFailed {
                    Image(systemName: "photo")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
            // 배경색을 두지 않아 이미지 뒤에 회색 배경이 보이지 않습니다.
            // 좌/우 끝까지 붙는 느낌 (클립/라운드 없음)
            .background(Color.clear)
            .frame(maxWidth: .infinity)
            .frame(height: 220, alignment: .top)
            .clipped()
            .task(id: brand.logoPath ?? "") {
                await loadLogoIfNeeded()
            }

            // 브랜드 이름 + 좋아요 수
            VStack(alignment: .leading, spacing: 6) {
                Text(brand.name)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("좋아요 \(brand.metrics.likeCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            // 분리선
            Divider()
                .padding(.horizontal, 16)
        }
    }

    private func loadLogoIfNeeded() async {
        // 이미 로딩된 이미지가 있거나 실패 상태면 재시도하지 않음(원하면 정책 바꿔도 됨)
        if uiImage != nil || loadFailed { return }

        guard
            let path = brand.logoPath,
            path.isEmpty == false,
            let cacheKey
        else {
            loadFailed = true
            return
        }

        do {
            // BrandLogoImageStore 내부에서 캐시/중복 다운로드 방지가 처리됩니다.
            let image = try await imageLoader.loadImage(
                path: path,
                cacheKey: cacheKey,
                maxBytes: maxBytes
            )
            uiImage = image
        } catch {
            loadFailed = true
        }
    }
}
