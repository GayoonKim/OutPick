//
//  LookbookHomeView.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import SwiftUI
import FirebaseFirestore

#if canImport(UIKit)
import UIKit
#endif

import SwiftUI

struct LookbookHomeView: View {
    @StateObject private var viewModel: LookbookHomeViewModel

    /// SceneDelegate/AppContainer에서 동일 인스턴스를 주입하면
    /// 룩북 탭 진입 시 “이미 로딩된 것처럼” 보이는 UX를 만들 수 있습니다.
    init(viewModel: LookbookHomeViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        Group {
            switch viewModel.phase {
            case .idle, .loading:
                VStack(spacing: 12) {
                    ProgressView()
                    Text("로딩 중...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

            case .failed(let message):
                VStack(spacing: 12) {
                    Text("불러오기 실패")
                        .font(.headline)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Button("다시 시도") {
                        Task { await viewModel.retry() }
                    }
                }

            case .ready:
                List {
                    ForEach(viewModel.brands) { brand in
                        BrandRowView(brand: brand, imageLoader: viewModel.imageLoader)
                            .onAppear {
                                Task { await viewModel.loadNextPageIfNeeded(current: brand) }
                            }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.preloadIfNeeded()
        }
    }
}

#Preview {
    LookbookHomeView(viewModel: LookbookHomeViewModel())
}
