//
//  LookbookHomeView.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import SwiftUI
import FirebaseFirestore
import FirebaseStorage

#if canImport(UIKit)
import UIKit
#endif

struct LookbookHomeView: View {
    @StateObject private var viewModel: LookbookHomeViewModel
    @State private var selectedBrandID: Brand.ID?
    @State private var isPresentingCreateBrand = false
    private let provider: LookbookRepositoryProvider

    /// SceneDelegate/AppContainer에서 동일 인스턴스를 주입하면
    /// 룩북 탭 진입 시 “이미 로딩된 것처럼” 보이는 UX를 만들 수 있습니다.
    init(viewModel: LookbookHomeViewModel, provider: LookbookRepositoryProvider) {
        self.provider = provider
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationView {
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
                            ZStack {
                                BrandRowView(brand: brand, imageLoader: viewModel.imageLoader)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedBrandID = brand.id
                                    }

                                NavigationLink(
                                    destination: BrandDetailView(
                                        brand: brand,
                                        imageLoader: viewModel.imageLoader
                                        // maxBytes: 필요하면 여기서 ViewModel과 동일 값으로 넘기기
                                    ),
                                    tag: brand.id,
                                    selection: $selectedBrandID
                                ) {
                                    EmptyView()
                                }
                                .hidden()
                            }
                            .onAppear {
                                Task { await viewModel.loadNextPageIfNeeded(current: brand) }
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("룩북")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isPresentingCreateBrand = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("브랜드 추가")
                }
            }
            .sheet(isPresented: $isPresentingCreateBrand) {
                NavigationView {
                    CreateBrandView(provider: provider)
                        .navigationTitle("브랜드 등록")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .navigationViewStyle(StackNavigationViewStyle())
            }
        }
        // iOS 15(iPad 포함)에서 기본 분할 내비게이션 형태가 뜨는 것을 방지하기 위해 stack 스타일을 강제합니다.
        .navigationViewStyle(StackNavigationViewStyle())
        .task {
            await viewModel.preloadIfNeeded()
        }
    }
}

#Preview {
    let provider = LookbookRepositoryProvider.shared
    let vm = LookbookHomeViewModel(
        repo: provider.brandRepository,
        imageLoader: BrandLogoImageStore(),
        initialBrandLimit: 20,
        prefetchLogoCount: 12
    )
    LookbookHomeView(viewModel: vm, provider: provider)
}
