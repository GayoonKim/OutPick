//
//  AdminBrandManagementView.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import SwiftUI
import UIKit

struct AdminBrandManagementView: View {
    @StateObject private var viewModel: AdminBrandManagementViewModel
    private let coordinator: LookbookCoordinator
    private let brandImageCache: any BrandImageCacheProtocol
    private let seasonAdditionSheetFactory: (Brand, @escaping () -> Void) -> AnyView
    private let importManagementSheetFactory: (Brand) -> AnyView

    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @State private var isImagePickerPresented = false
    @State private var isPresentingSeasonAddition = false
    @State private var isPresentingImportManagement = false

    init(
        viewModel: AdminBrandManagementViewModel,
        coordinator: LookbookCoordinator,
        brandImageCache: any BrandImageCacheProtocol,
        seasonAdditionSheetFactory: @escaping (Brand, @escaping () -> Void) -> AnyView,
        importManagementSheetFactory: @escaping (Brand) -> AnyView
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coordinator = coordinator
        self.brandImageCache = brandImageCache
        self.seasonAdditionSheetFactory = seasonAdditionSheetFactory
        self.importManagementSheetFactory = importManagementSheetFactory
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isDirectBrandMode == false {
                    searchSection
                } else if viewModel.isLoadingInitialBrand {
                    loadingSection
                }

                if let selectedBrand = viewModel.selectedBrand {
                    editSection
                    logoSection
                    if brandAdminSessionStore.canManageBrandManagers(brandID: selectedBrand.id) {
                        managerSection
                    }
                    importSection(selectedBrand)
                }

                if let message = viewModel.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OutPickTheme.SwiftUIColor.warning.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .lookbookNavigationBar(
            title: "브랜드 관리",
            showsBackButton: true,
            onBack: { coordinator.pop() }
        )
        .task {
            await viewModel.loadInitialBrandIfNeeded()
        }
        .sheet(isPresented: $isImagePickerPresented) {
            PhotoPicker { data in
                guard let data, let image = UIImage(data: data) else {
                    viewModel.message = "로고 이미지를 불러오지 못했습니다."
                    return
                }
                viewModel.setPickedLogo(image: image, data: data)
            }
        }
        .sheet(isPresented: $isPresentingSeasonAddition) {
            if let selectedBrand = viewModel.selectedBrand {
                seasonAdditionSheetFactory(selectedBrand) {
                    isPresentingSeasonAddition = false
                }
            }
        }
        .sheet(isPresented: $isPresentingImportManagement) {
            if let selectedBrand = viewModel.selectedBrand {
                importManagementSheetFactory(selectedBrand)
            }
        }
    }

    private var searchSection: some View {
        adminSection {
            VStack(alignment: .leading, spacing: 12) {
                Text("브랜드 선택")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                searchField

                ForEach(visibleSearchResults) { brand in
                    Button {
                        viewModel.selectBrand(brand)
                    } label: {
                        HStack(spacing: 12) {
                            LookbookAssetImageView(
                                primaryPath: brand.logoThumbPath,
                                secondaryPath: brand.logoDetailPath ?? brand.logoOriginalPath,
                                remoteURL: nil,
                                sourcePageURL: nil,
                                brandImageCache: brandImageCache,
                                maxBytes: 800_000
                            )
                            .frame(width: 42, height: 42)
                            .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(brand.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                                Text(brand.websiteURL ?? "공식 URL 없음")
                                    .font(.caption)
                                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                                    .lineLimit(1)
                            }

                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)
                        }
                        .padding(12)
                        .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var loadingSection: some View {
        adminSection {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(OutPickTheme.SwiftUIColor.accent)
                Text("브랜드 정보를 불러오는 중입니다.")
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)

            TextField("브랜드명 검색", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

            if viewModel.isSearching {
                ProgressView()
                    .tint(OutPickTheme.SwiftUIColor.accent)
            } else if viewModel.searchText.isEmpty == false {
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
        .background(OutPickTheme.SwiftUIColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var editSection: some View {
        adminSection {
            VStack(alignment: .leading, spacing: 14) {
                Text("브랜드 정보")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                adminTextField(title: "브랜드명", text: $viewModel.brandName)
                adminTextField(title: "공식 홈페이지 URL", text: $viewModel.websiteURLText)
                adminTextField(title: "룩북 목록 URL", text: $viewModel.lookbookArchiveURLText)

                if brandAdminSessionStore.isTotalAdmin {
                    Toggle(isOn: $viewModel.isFeatured) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("피처드")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                            Text("총 관리자 전용 필드입니다.")
                                .font(.caption)
                                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        }
                    }
                    .tint(OutPickTheme.SwiftUIColor.accent)
                }

                primaryButton(
                    title: "브랜드 정보 저장",
                    isLoading: viewModel.isSavingBrand,
                    isDisabled: !viewModel.canSaveBrand
                ) {
                    Task {
                        await viewModel.saveBrand(
                            canUpdateFeatured: brandAdminSessionStore.isTotalAdmin
                        )
                    }
                }
            }
        }
    }

    private var logoSection: some View {
        adminSection {
            VStack(alignment: .leading, spacing: 14) {
                Text("로고")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                Button {
                    isImagePickerPresented = true
                } label: {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text(viewModel.selectedLogoImage == nil ? "로고 이미지 선택" : "로고 이미지 다시 선택")
                        Spacer()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
                    .padding(14)
                    .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                if let selectedLogoImage = viewModel.selectedLogoImage {
                    Image(uiImage: selectedLogoImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button("선택 이미지 제거") {
                        viewModel.clearPickedLogo()
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.destructive)
                }

                primaryButton(
                    title: "로고 저장",
                    isLoading: viewModel.isUploadingLogo,
                    isDisabled: !viewModel.canUploadLogo
                ) {
                    Task { await viewModel.uploadLogo() }
                }
            }
        }
    }

    private var managerSection: some View {
        adminSection {
            VStack(alignment: .leading, spacing: 14) {
                Text("관리자")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                adminTextField(title: "사용자 이메일", text: $viewModel.managerEmail)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)

                Picker("역할", selection: $viewModel.managerRole) {
                    ForEach(BrandManagerRole.allCases) { role in
                        Text(role.title).tag(role)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 10) {
                    secondaryButton(
                        title: "삭제",
                        isDisabled: !viewModel.canMutateManager
                    ) {
                        Task { await viewModel.removeManager() }
                    }

                    primaryButton(
                        title: "추가",
                        isLoading: viewModel.isMutatingManager,
                        isDisabled: !viewModel.canMutateManager
                    ) {
                        Task { await viewModel.addManager() }
                    }
                }
            }
        }
    }

    private func importSection(_ brand: Brand) -> some View {
        adminSection {
            VStack(alignment: .leading, spacing: 14) {
                Text("시즌 가져오기")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                HStack(spacing: 10) {
                    secondaryButton(
                        title: "시즌 찾아오기",
                        isDisabled: !hasLookbookArchiveURL(brand)
                    ) {
                        isPresentingSeasonAddition = true
                    }

                    secondaryButton(title: "진행 현황") {
                        isPresentingImportManagement = true
                    }
                }
            }
        }
    }

    private func adminSection<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(16)
            .background(OutPickTheme.SwiftUIColor.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
            )
    }

    private func adminTextField(
        title: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            TextField(title, text: text)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func primaryButton(
        title: String,
        isLoading: Bool = false,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                if isLoading {
                    ProgressView()
                        .tint(OutPickTheme.SwiftUIColor.backgroundBase)
                } else {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                }
                Spacer()
            }
            .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
            .padding(.vertical, 13)
            .background(OutPickTheme.SwiftUIColor.accent)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func secondaryButton(
        title: String,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func hasLookbookArchiveURL(_ brand: Brand) -> Bool {
        guard let value = brand.lookbookArchiveURL else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var visibleSearchResults: [Brand] {
        guard brandAdminSessionStore.isTotalAdmin == false else {
            return viewModel.searchResults
        }

        return viewModel.searchResults.filter { brand in
            brandAdminSessionStore.canWrite(brandID: brand.id)
        }
    }
}
