//
//  BrandDetailView.swift
//  OutPick
//
//  Created by 김가윤 on 1/3/26.
//

import SwiftUI

struct BrandDetailView: View {
    private enum SeasonCreationSheet: String, Identifiable {
        case manual
        case importFromURL

        var id: String { rawValue }
    }

    let brand: Brand
    let brandImageCache: any BrandImageCacheProtocol
    let maxBytes: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.repositoryProvider) private var provider
    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @StateObject private var viewModel = BrandDetailViewModel()
    @State private var isPresentSeasonCreationDialog: Bool = false
    @State private var activeSeasonSheet: SeasonCreationSheet?
    @State private var seasonImportFeedbackMessage: String?

    init(
        brand: Brand,
        brandImageCache: any BrandImageCacheProtocol,
        maxBytes: Int = 1_000_000
    ) {
        self.brand = brand
        self.brandImageCache = brandImageCache
        self.maxBytes = maxBytes
    }

    var body: some View {
        List {
            BrandDetailHeaderView(
                brand: brand,
                brandImageCache: brandImageCache,
                maxBytes: maxBytes
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)

            BrandDetailSeasonsGridView(
                seasons: viewModel.seasons,
                latestSeasonImportJob: viewModel.latestSeasonImportJob,
                isLoading: viewModel.isLoading,
                errorMessage: viewModel.errorMessage,
                importJobErrorMessage: viewModel.importJobErrorMessage,
                canRequestSeasonImport: brandAdminSessionStore.canWrite(brandID: brand.id),
                onTapSeasonImportCTA: {
                    activeSeasonSheet = .importFromURL
                },
                brandImageCache: brandImageCache,
                maxBytes: maxBytes
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle(brand.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .tint(.black)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.black)
                }
                .accessibilityLabel("뒤로 가기")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if brandAdminSessionStore.canWrite(brandID: brand.id) {
                    Button {
                        isPresentSeasonCreationDialog = true
                    } label: {
                        Text("시즌 추가")
                            .foregroundStyle(.black)
                    }
                    .accessibilityLabel("시즌 추가")
                }
            }
        }
        .confirmationDialog(
            "시즌 추가 방식을 선택해주세요",
            isPresented: $isPresentSeasonCreationDialog,
            titleVisibility: .visible
        ) {
            Button("직접 입력으로 추가") {
                activeSeasonSheet = .manual
            }
            Button("시즌 URL로 등록") {
                activeSeasonSheet = .importFromURL
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("수동 입력 또는 시즌 URL import 요청 중 하나를 선택할 수 있습니다.")
        }
        .sheet(item: $activeSeasonSheet, onDismiss: {
            Task {
                await viewModel.refreshContents(
                    brandID: brand.id,
                    seasonRepository: provider.seasonRepository,
                    seasonImportJobRepository: provider.seasonImportJobRepository
                )
            }
        }) { sheet in
            switch sheet {
            case .manual:
                CreateSeasonView(
                    viewModel: CreateSeasonViewModel(
                        brandID: brand.id,
                        seasonRepository: provider.seasonRepository,
                        tagRepository: provider.tagRepository,
                        tagAliasRepository: provider.tagAliasRepository,
                        tagConceptRepository: provider.tagConceptRepository
                    )
                )
            case .importFromURL:
                CreateSeasonFromURLView(
                    viewModel: CreateSeasonFromURLViewModel(
                        brandID: brand.id,
                        seasonImportRepository: provider.seasonImportRepository
                    )
                ) { receipt in
                    seasonImportFeedbackMessage =
                        """
                        시즌 URL import 요청이 생성되었습니다.
                        요청 상태: \(receipt.status)

                        현재 단계에서는 import job 생성까지만 연결되어 있습니다.
                        다음 단계에서 수집 워커를 붙이면 이 요청을 기반으로 실제 시즌/포스트 import가 이어집니다.
                        """
                }
            }
        }
        .alert(
            "시즌 등록 요청 완료",
            isPresented: Binding(
                get: { seasonImportFeedbackMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        seasonImportFeedbackMessage = nil
                    }
                }
            )
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text(seasonImportFeedbackMessage ?? "")
        }
        .task {
            await viewModel.loadContentsIfNeeded(
                brandID: brand.id,
                seasonRepository: provider.seasonRepository,
                seasonImportJobRepository: provider.seasonImportJobRepository
            )
        }
    }
}
