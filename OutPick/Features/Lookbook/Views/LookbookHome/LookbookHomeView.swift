//
//  LookbookHomeView.swift
//  OutPick
//
//  Created by 김가윤 on 12/18/25.
//

import SwiftUI

struct LookbookHomeView: View {
    private let pullToRefreshMinimumVisibleDuration: TimeInterval = 0.6

    @StateObject private var viewModel: LookbookHomeViewModel

    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @State private var selectedBrandID: Brand.ID?
    @State private var isPresentingCreateBrand = false
    @State private var createdBrandIDForSelection: Brand.ID?

    private let coordinator: LookbookCoordinator

    /// SceneDelegate/AppContainer에서 동일 인스턴스를 주입하면
    /// 룩북 탭 진입 시 “이미 로딩된 것처럼” 보이는 UX를 만들 수 있습니다.
    init(viewModel: LookbookHomeViewModel, coordinator: LookbookCoordinator) {
        self.coordinator = coordinator
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationView {
            mainContent
        }
        .tint(.black)
        .navigationViewStyle(StackNavigationViewStyle())
        .fullScreenCover(isPresented: $isPresentingCreateBrand, onDismiss: {
            guard let createdBrandIDForSelection else { return }

            Task {
                await brandAdminSessionStore.refreshWritableBrands(force: true)
                await viewModel.retry()
                await viewModel.syncCreatedBrand(brandID: createdBrandIDForSelection)
                selectedBrandID = createdBrandIDForSelection
                self.createdBrandIDForSelection = nil
            }
        }) {
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
                                destination: coordinator.makeBrandDetailView(brand: brand),
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
                .refreshable {
                    await refreshWithMinimumIndicatorDuration()
                }
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
                            Text("브랜드 추가")
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
            coordinator.makeCreateBrandFlow { createdBrandID in
                createdBrandIDForSelection = createdBrandID
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func refreshWithMinimumIndicatorDuration() async {
        let startedAt = Date()

        await viewModel.refreshKeepingVisibleContent()

        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed < pullToRefreshMinimumVisibleDuration else { return }

        // 새로고침이 너무 빨리 끝나도 인디케이터가 잠깐 유지되도록 최소 표시 시간을 맞춥니다.
        let remainingNanoseconds = UInt64(
            (pullToRefreshMinimumVisibleDuration - elapsed) * 1_000_000_000
        )
        try? await Task.sleep(nanoseconds: remainingNanoseconds)
    }
}

#Preview {
    let provider = LookbookRepositoryProvider.shared
    let brandAdminSessionStore = BrandAdminSessionStore()
    let container = LookbookContainer(
        provider: provider,
        brandAdminSessionStore: brandAdminSessionStore
    )
    let coordinator = LookbookCoordinator(container: container)
    let vm = LookbookHomeViewModel(
        repo: provider.brandRepository,
        brandAdminSessionStore: brandAdminSessionStore,
        brandImageCache: provider.brandImageCache,
        initialBrandLimit: 12,
        prefetchLogoCount: 4
    )
    LookbookHomeView(viewModel: vm, coordinator: coordinator)
        .environmentObject(brandAdminSessionStore)
}
