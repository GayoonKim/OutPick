//
//  SeasonCoverThumbView.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/26.
//

import SwiftUI

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct SeasonCoverThumbView: View {
    let thumbPath: String?
    let fallbackPath: String?
    let imageLoader: any ImageLoading
    let maxBytes: Int

    @State private var uiImage: UIImage?
    @State private var isLoading: Bool = false

    var body: some View {
        ZStack {
            if let uiImage {
                GeometryReader { geo in
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        // 상단부터 채우고 아래쪽이 잘리도록 정렬
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                        .clipped()
                }
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.gray.opacity(0.15))

                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "photo")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // 부모가 준 프레임을 ZStack이 확실히 채우게 보장
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard uiImage == nil, !isLoading else { return }

        let targetPath = thumbPath ?? fallbackPath
        guard let targetPath, !targetPath.isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            uiImage = try await imageLoader.loadImage(
                path: targetPath,
                cacheKey: targetPath,
                maxBytes: maxBytes
            )
        } catch {
            // 실패 시 플레이스홀더 유지
        }
    }
}
