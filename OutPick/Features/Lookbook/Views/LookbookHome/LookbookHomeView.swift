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
        mainContent
            .lookbookNavigationBar(title: "OutPick") {
                if viewModel.canCreateBrand {
                    LookbookNavigationTextButton(
                        title: "브랜드 추가",
                        accessibilityLabel: "브랜드 추가"
                    ) {
                        isPresentingCreateBrand = true
                    }
                }
            }
            .tint(OutPickTheme.SwiftUIColor.accent)
            .fullScreenCover(isPresented: $isPresentingCreateBrand, onDismiss: {
                guard let createdBrandIDForSelection else { return }

                Task {
                    await brandAdminSessionStore.refreshWritableBrands(force: true)
                    await viewModel.retry()
                    await viewModel.syncCreatedBrand(brandID: createdBrandIDForSelection)
                    await MainActor.run {
                        if let createdBrand = viewModel.brands.first(where: { $0.id == createdBrandIDForSelection }) {
                            coordinator.pushBrandDetail(brand: createdBrand)
                        }
                        self.createdBrandIDForSelection = nil
                    }
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
                        .tint(OutPickTheme.SwiftUIColor.accent)
                    Text("로딩 중...")
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                }

            case .failed(let message):
                VStack(spacing: 12) {
                    Text("불러오기 실패")
                        .font(.headline)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

                    Button("다시 시도") {
                        Task { await viewModel.retry() }
                    }
                    .tint(OutPickTheme.SwiftUIColor.accent)
                }

            case .ready:
                List {
                    ForEach(viewModel.brands) { brand in
                        ZStack {
                            BrandRowView(brand: brand, brandImageCache: viewModel.brandImageCache)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    coordinator.pushBrandDetail(brand: brand)
                                }
                        }
                        .onAppear {
                            Task { await viewModel.loadNextPageIfNeeded(current: brand) }
                        }
                    }
                }
                .listStyle(.plain)
                .outpickHiddenScrollContentBackground()
                .background(OutPickTheme.SwiftUIColor.backgroundBase)
                .refreshable {
                    await refreshWithMinimumIndicatorDuration()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
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

private extension View {
    @ViewBuilder
    func outpickHiddenScrollContentBackground() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

private final class PreviewAvatarImageManager: AvatarImageManaging {
    func cachedAvatar(for path: String) async -> UIImage? { nil }
    func loadAvatar(for path: String, maxBytes: Int) async throws -> UIImage { UIImage() }
    func prefetchAvatars(paths: [String], maxBytes: Int, maxConcurrent: Int) async {}
    func storeAvatarDataToCache(_ data: Data, for path: String) async throws {}
    func removeCachedAvatar(for path: String) async {}
}

#Preview {
    let provider = LookbookRepositoryProvider.shared
    let brandAdminSessionStore = BrandAdminSessionStore()
    let container = LookbookContainer(
        provider: provider,
        brandAdminSessionStore: brandAdminSessionStore,
        avatarImageManager: PreviewAvatarImageManager()
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
