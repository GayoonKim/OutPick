import SwiftUI

struct InterestedStyleBrandListView: View {
    @StateObject private var viewModel: InterestedStyleBrandListViewModel
    private let coordinator: LookbookCoordinator

    init(
        viewModel: InterestedStyleBrandListViewModel,
        coordinator: LookbookCoordinator
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coordinator = coordinator
    }

    var body: some View {
        content
            .lookbookNavigationBar(
                title: "관심 스타일",
                showsBackButton: true,
                onBack: { coordinator.pop() }
            )
            .background(OutPickTheme.SwiftUIColor.backgroundBase)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading where viewModel.brands.isEmpty:
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            emptyState

        case .failed(let message) where viewModel.brands.isEmpty:
            failureState(message)

        case .loading, .ready, .failed(_):
            brandList
        }
    }

    private var brandList: some View {
        List {
            ForEach(viewModel.brands) { brand in
                BrandRowView(
                    brand: brand,
                    brandImageCache: viewModel.brandImageCache
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    coordinator.pushBrandDetail(brand: brand)
                }
                .onAppear {
                    Task {
                        await viewModel.loadNextPageIfNeeded(current: brand)
                    }
                }
            }

            if viewModel.isLoadingNext {
                ProgressView()
                    .tint(OutPickTheme.SwiftUIColor.accent)
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if let message = viewModel.loadMoreErrorMessage {
                VStack(spacing: 10) {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    Button("다시 시도") {
                        Task { await viewModel.retryLoadMore() }
                    }
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
                }
                .frame(maxWidth: .infinity)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .interestedStyleHiddenScrollContentBackground()
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
        .refreshable {
            await viewModel.refresh()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("아직 연결된 브랜드가 없어요")
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            Text("관심 스타일을 편집하거나 알고 있는 브랜드를 요청해 주세요")
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 14) {
            Text(message)
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            Button("다시 시도") {
                Task { await viewModel.refresh() }
            }
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension View {
    @ViewBuilder
    func interestedStyleHiddenScrollContentBackground() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
