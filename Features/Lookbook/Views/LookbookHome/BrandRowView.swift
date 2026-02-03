//
//  BrandRowView.swift
//  OutPick
//
//  Created by 김가윤 on 12/31/25.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct BrandRowView: View {
    let brand: Brand
    let imageLoader: any ImageLoading

    #if canImport(UIKit)
    @State private var uiImage: UIImage? = nil
    #endif

    @State private var loadFailed: Bool = false

    // 목록 썸네일이므로 다운로드 최대 용량을 낮게 유지합니다. (대략 1MB)
    private let maxLogoBytes: Int = 1 * 1024 * 1024

    // 콜라주(현재는 이미지 1장만 사용) 영역 크기
    private let collageHeight: CGFloat = 240
    private let collageCornerRadius: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            collageView

            Text(brand.name)
                .font(.headline)

            HStack(spacing: 10) {
                likeChip(value: brand.metrics.likeCount) // 좋아요만 표시
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
        .task {
            await loadLogoIfNeeded()
        }
    }

    private var collageView: some View {
        GeometryReader { geo in
            imageSlot
                .frame(width: geo.size.width, height: collageHeight, alignment: .top)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: collageCornerRadius))
        }
        .frame(height: collageHeight)
    }

    @ViewBuilder
    private var imageSlot: some View {
        #if canImport(UIKit)
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                // 얼굴이 위쪽에서 잘리는 경우가 많아서 상단 기준으로 크롭되도록 정렬을 고정합니다.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            placeholderSlot
        }
        #else
        placeholderSlot
        #endif
    }

    private var placeholderSlot: some View {
        Rectangle()
            .fill(Color(.tertiarySystemFill))
            .overlay {
                Image(systemName: loadFailed ? "exclamationmark.triangle" : "photo")
                    .font(.title3)
            }
    }

    private func likeChip(value: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
            Text("\(value)")
                .font(.subheadline)
                .monospacedDigit()
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            Capsule().fill(Color(.tertiarySystemFill))
        )
    }

    // MARK: - Loading

    @MainActor
    private func loadLogoIfNeeded() async {
        // 목록에서는 썸네일 경로를 우선 사용하고, 없으면 기존 logoPath로 폴백합니다.
        let resolvedPath = brand.logoThumbPath ?? brand.logoOriginalPath
        guard let path = resolvedPath, !path.isEmpty else { return }

        // 이미 로드했거나 실패했다면 중복 호출 방지
        #if canImport(UIKit)
        if uiImage != nil || loadFailed { return }
        #else
        if loadFailed { return }
        #endif

        do {
            #if canImport(UIKit)
            // 캐시 키는 용도까지 포함해두면 안전합니다.
            let cacheKey = "brandLogoThumb|\(path)"
            let image = try await imageLoader.loadImage(
                path: path,
                cacheKey: cacheKey,
                maxBytes: maxLogoBytes
            )
            uiImage = image
            #endif
        } catch {
            loadFailed = true
        }
    }
}
