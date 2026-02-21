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
    @StateObject private var router = LookbookRouter()

    // iOS 15 fallback navigation state
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
        Group {
            if #available(iOS 16.0, *) {
                modernNavigationBody
            } else {
                legacyNavigationBody
            }
        }
        .task {
            await viewModel.loadInitialPageIfNeeded()
        }
    }

    @available(iOS 16.0, *)
    private var modernNavigationBody: some View {
        NavigationStack(path: $router.path) {
            mainContent(
                onCreateBrandTap: { router.present(.createBrand) },
                onSelectBrand: { brand in router.pushBrand(brand.id) },
                usesLegacyNavigationLink: false
            )
            .navigationDestination(for: LookbookRoute.self) { route in
                routeDestination(for: route)
            }
        }
        .sheet(item: $router.presentedSheet) { sheet in
            switch sheet {
            case .createBrand:
                createBrandSheet
            }
        }
    }

    private var legacyNavigationBody: some View {
        NavigationView {
            mainContent(
                onCreateBrandTap: { isPresentingCreateBrand = true },
                onSelectBrand: { brand in selectedBrandID = brand.id },
                usesLegacyNavigationLink: true
            )
        }
        // iOS 15(iPad 포함)에서 기본 분할 내비게이션 형태가 뜨는 것을 방지하기 위해 stack 스타일을 강제합니다.
        .navigationViewStyle(StackNavigationViewStyle())
        .sheet(isPresented: $isPresentingCreateBrand) {
            createBrandSheet
        }
    }

    @ViewBuilder
    private func mainContent(
        onCreateBrandTap: @escaping () -> Void,
        onSelectBrand: @escaping (Brand) -> Void,
        usesLegacyNavigationLink: Bool
    ) -> some View {
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
                        if usesLegacyNavigationLink {
                            ZStack {
                                BrandRowView(brand: brand, brandImageCache: viewModel.brandImageCache)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        onSelectBrand(brand)
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
                        } else {
                            BrandRowView(brand: brand, brandImageCache: viewModel.brandImageCache)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    onSelectBrand(brand)
                                }
                                .onAppear {
                                    Task { await viewModel.loadNextPageIfNeeded(current: brand) }
                                }
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
                Button {
                    onCreateBrandTap()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                        Text("브랜드")
                    }
                    .lineLimit(1)
                }
                .accessibilityLabel("브랜드 추가")
                .foregroundStyle(.primary)
            }
        }
    }

    @available(iOS 16.0, *)
    @ViewBuilder
    private func routeDestination(for route: LookbookRoute) -> some View {
        switch route {
        case .brand(let brandID):
            if let brand = viewModel.brands.first(where: { $0.id == brandID }) {
                BrandDetailView(
                    brand: brand,
                    brandImageCache: viewModel.brandImageCache,
                    onSelectSeason: { season in
                        router.pushSeason(brandID: brandID, seasonID: season.id)
                    }
                )
            } else {
                MissingRouteView(
                    title: "브랜드를 찾을 수 없습니다.",
                    subtitle: "브랜드 목록을 새로고침한 뒤 다시 시도해주세요."
                )
            }

        case .season(let brandID, let seasonID):
            SeasonDetailView(
                brandID: brandID,
                seasonID: seasonID,
                onSelectPost: { postID in
                    router.pushPost(brandID: brandID, seasonID: seasonID, postID: postID)
                }
            )

        case .post(let brandID, let seasonID, let postID):
            PostDetailView(
                brandID: brandID,
                seasonID: seasonID,
                postID: postID
            )
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

private struct MissingRouteView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}

#Preview {
    let provider = LookbookRepositoryProvider.shared
    let vm = LookbookHomeViewModel(
        repo: provider.brandRepository,
        brandImageCache: provider.brandImageCache,
        initialBrandLimit: 12,
        prefetchLogoCount: 4
    )
    LookbookHomeView(viewModel: vm, provider: provider)
}
