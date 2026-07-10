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
                HStack(spacing: 8) {
                    LookbookNavigationTextButton(
                        title: "브랜드 요청",
                        accessibilityLabel: "브랜드 요청 상황"
                    ) {
                        coordinator.pushMyBrandRequests(initialScope: .active)
                    }

                    if brandAdminSessionStore.isTotalAdmin {
                        LookbookNavigationTextButton(
                            title: "관리자",
                            accessibilityLabel: "Lookbook 관리자"
                        ) {
                            coordinator.pushAdminHome { createdBrandID in
                                Task {
                                    await handleCreatedBrand(createdBrandID)
                                }
                            }
                        }
                    }
                }
            }
            .tint(OutPickTheme.SwiftUIColor.accent)
            .outpickDismissKeyboardOnTap()
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
                VStack(spacing: 0) {
                    searchBar
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)

                    if viewModel.isSearching {
                        searchContent
                    } else {
                        brandListContent
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)

            TextField("브랜드 검색", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            if viewModel.searchText.isEmpty == false {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("검색어 지우기")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var brandListContent: some View {
        List {
            ForEach(viewModel.brands) { brand in
                brandRow(brand)
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

    @ViewBuilder
    private var searchContent: some View {
        switch viewModel.searchPhase {
        case .idle, .searching:
            Spacer()
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)
            Spacer()

        case .results:
            List {
                ForEach(viewModel.searchResults) { brand in
                    brandRow(brand)
                }
            }
            .listStyle(.plain)
            .outpickHiddenScrollContentBackground()
            .background(OutPickTheme.SwiftUIColor.backgroundBase)

        case .empty:
            Spacer()
            VStack(spacing: 14) {
                Text("찾는 브랜드가 없어요")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                Text("브랜드 추가를 요청하면 OutPick에서 공식 룩북 확인 가능 여부를 검토해요.")
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    coordinator.pushBrandRequest(
                        initialBrandName: viewModel.normalizedSearchText
                    )
                } label: {
                    Text("브랜드 요청하기")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                        .frame(height: 44)
                        .padding(.horizontal, 18)
                        .background(OutPickTheme.SwiftUIColor.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            Spacer()

        case .failed(let message):
            Spacer()
            VStack(spacing: 12) {
                Text("검색하지 못했어요")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func brandRow(_ brand: Brand) -> some View {
        ZStack {
            BrandRowView(brand: brand, brandImageCache: viewModel.brandImageCache)
                .contentShape(Rectangle())
                .onTapGesture {
                    coordinator.pushBrandDetail(brand: brand)
                }
        }
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

    private func handleCreatedBrand(_ createdBrandID: Brand.ID) async {
        await brandAdminSessionStore.refreshWritableBrands(force: true)
        await viewModel.retry()
        await viewModel.syncCreatedBrand(brandID: createdBrandID)

        if let createdBrand = viewModel.brands.first(where: { $0.id == createdBrandID }) {
            coordinator.pushBrandDetail(brand: createdBrand)
        }
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
        searchUseCase: SearchBrandsUseCase(
            repository: provider.brandSearchRepository
        ),
        brandAdminSessionStore: brandAdminSessionStore,
        brandImageCache: provider.brandImageCache,
        initialBrandLimit: 12,
        prefetchLogoCount: 4
    )
    LookbookHomeView(viewModel: vm, coordinator: coordinator)
        .environmentObject(brandAdminSessionStore)
}
