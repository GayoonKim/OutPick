//
//  LookbookHomeView.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import SwiftUI

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
            mainContent
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $isPresentingCreateBrand) {
            createBrandSheet
        }
        .task {
            await viewModel.loadInitialPageIfNeeded()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
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
                            BrandRowView(brand: brand, brandImageCache: viewModel.brandImageCache)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedBrandID = brand.id
                                }

                            NavigationLink(
                                destination: BrandDetailView(
                                    brand: brand,
                                    brandImageCache: viewModel.brandImageCache
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Text("OutPick")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.canCreateBrand {
                    Button {
                        isPresentingCreateBrand = true
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "plus")
                            Text("브랜드")
                        }
                        .lineLimit(1)
                    }
                    .accessibilityLabel("브랜드 추가")
                    .foregroundStyle(.primary)
                } else {
                    EmptyView()
                }
            }
        }
    }

    private var createBrandSheet: some View {
        NavigationView {
            CreateBrandView(provider: provider)
                .navigationTitle("브랜드 등록")
                .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#Preview {
    let provider = LookbookRepositoryProvider.shared
    let brandAdminSessionStore = BrandAdminSessionStore()
    let vm = LookbookHomeViewModel(
        repo: provider.brandRepository,
        brandAdminSessionStore: brandAdminSessionStore,
        brandImageCache: provider.brandImageCache,
        initialBrandLimit: 12,
        prefetchLogoCount: 4
    )
    LookbookHomeView(viewModel: vm, provider: provider)
        .environmentObject(brandAdminSessionStore)
}
