//
//  AdminBrandManagementView.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import SwiftUI
import UIKit

private enum AdminBrandManagementTab: String, CaseIterable, Identifiable {
    case info
    case managers
    case importSeasons
    case deletion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: return "정보"
        case .managers: return "관리자"
        case .importSeasons: return "시즌 가져오기"
        case .deletion: return "삭제"
        }
    }

    var subtitle: String {
        switch self {
        case .info: return "브랜드 정보와 로고 수정"
        case .managers: return "브랜드 소유자와 관리자 추가/삭제"
        case .importSeasons: return "시즌 후보 찾기와 가져오기 현황"
        case .deletion: return "브랜드/시즌/포스트 삭제 요청 관리"
        }
    }

    var systemImage: String {
        switch self {
        case .info: return "info.circle"
        case .managers: return "person.2"
        case .importSeasons: return "square.and.arrow.down"
        case .deletion: return "trash"
        }
    }
}

private enum AdminBrandImportTab: String, CaseIterable, Identifiable {
    case discover
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discover: return "시즌 찾아오기"
        case .status: return "현황"
        }
    }
}

struct AdminBrandManagementView: View {
    @StateObject private var viewModel: AdminBrandManagementViewModel
    private let coordinator: LookbookCoordinator
    private let brandImageCache: any BrandImageCacheProtocol
    private let seasonAdditionSheetFactory: (Brand, @escaping () -> Void) -> AnyView
    private let importManagementSheetFactory: (Brand) -> AnyView
    private let deletionManagementFactory: (Brand) -> AnyView

    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @State private var isImagePickerPresented = false
    @State private var isPresentingSeasonAddition = false
    @State private var selectedMenu: AdminBrandManagementTab?
    @State private var selectedImportTab: AdminBrandImportTab = .discover

    init(
        viewModel: AdminBrandManagementViewModel,
        coordinator: LookbookCoordinator,
        brandImageCache: any BrandImageCacheProtocol,
        seasonAdditionSheetFactory: @escaping (Brand, @escaping () -> Void) -> AnyView,
        importManagementSheetFactory: @escaping (Brand) -> AnyView,
        deletionManagementFactory: @escaping (Brand) -> AnyView
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coordinator = coordinator
        self.brandImageCache = brandImageCache
        self.seasonAdditionSheetFactory = seasonAdditionSheetFactory
        self.importManagementSheetFactory = importManagementSheetFactory
        self.deletionManagementFactory = deletionManagementFactory
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isLoadingInitialBrand {
                ScrollView {
                    loadingSection
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                }
            } else if let selectedBrand = viewModel.selectedBrand {
                if let selectedMenu, availableMenus(for: selectedBrand).contains(selectedMenu) {
                    selectedMenuContent(selectedMenu, for: selectedBrand)
                } else {
                    managementMenuList(for: selectedBrand)
                }
            } else {
                ScrollView {
                    emptyBrandSelectionSection
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                }
            }
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .lookbookNavigationBar(
            title: navigationTitle,
            showsBackButton: true,
            onBack: handleBack
        )
        .outpickDismissKeyboardOnTap()
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
                                if let englishName = brand.englishName, englishName.isEmpty == false {
                                    Text(englishName)
                                        .font(.caption)
                                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                                        .lineLimit(1)
                                }
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

    private var emptyBrandSelectionSection: some View {
        adminSection {
            VStack(alignment: .leading, spacing: 10) {
                Text("브랜드 상세에서 진입해주세요.")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                Text("브랜드 관리는 룩북 홈에서 브랜드를 검색한 뒤 상세 화면의 관리자 버튼으로 시작합니다.")
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func managementMenuList(for brand: Brand) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(availableMenus(for: brand)) { menu in
                    managementMenuButton(menu)
                }

                messageSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
    }

    private func managementMenuButton(_ menu: AdminBrandManagementTab) -> some View {
        Button {
            selectedMenu = menu
        } label: {
            HStack(spacing: 14) {
                Image(systemName: menu.systemImage)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(menu == .deletion ? OutPickTheme.SwiftUIColor.destructive : OutPickTheme.SwiftUIColor.accent)
                    .frame(width: 48, height: 48)
                    .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(menu.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .lineLimit(1)

                    Text(menu.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)
            }
            .padding(18)
            .background(OutPickTheme.SwiftUIColor.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(menu.title)
    }

    @ViewBuilder
    private func selectedMenuContent(
        _ menu: AdminBrandManagementTab,
        for brand: Brand
    ) -> some View {
        switch menu {
        case .info:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    editSection
                    logoSection(brand)
                    messageSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        case .managers:
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    managerSection
                    messageSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        case .importSeasons:
            importTabContent(for: brand)
        case .deletion:
            deletionManagementFactory(brand)
        }
    }

    @ViewBuilder
    private func importTabContent(for brand: Brand) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("시즌 가져오기 메뉴", selection: $selectedImportTab) {
                ForEach(AdminBrandImportTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 24)

            switch selectedImportTab {
            case .discover:
                ScrollView {
                    importDiscoverySection(brand)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                }
            case .status:
                importManagementSheetFactory(brand)
            }
        }
    }

    @ViewBuilder
    private var messageSection: some View {
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

    private func availableMenus(for brand: Brand) -> [AdminBrandManagementTab] {
        var tabs: [AdminBrandManagementTab] = [.info]
        if brandAdminSessionStore.canManageBrandManagers(brandID: brand.id) {
            tabs.append(.managers)
        }
        tabs.append(contentsOf: [.importSeasons, .deletion])
        return tabs
    }

    private var navigationTitle: String {
        selectedMenu?.title ?? "브랜드 관리"
    }

    private func handleBack() {
        if selectedMenu != nil {
            selectedMenu = nil
        } else {
            coordinator.pop()
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
                adminTextField(title: "영문 브랜드명", text: $viewModel.englishName)
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
                    isDisabled: !viewModel.canSaveBrand(
                        canUpdateFeatured: brandAdminSessionStore.isTotalAdmin
                    )
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

    private func logoSection(_ brand: Brand) -> some View {
        adminSection {
            VStack(alignment: .leading, spacing: 14) {
                Text("로고")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                LookbookAssetImageView(
                    primaryPath: brand.logoThumbPath,
                    secondaryPath: brand.logoDetailPath ?? brand.logoOriginalPath,
                    remoteURL: nil,
                    sourcePageURL: nil,
                    brandImageCache: brandImageCache,
                    maxBytes: 800_000
                )
                .frame(width: 96, height: 96)
                .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
                )

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

    private func importDiscoverySection(_ brand: Brand) -> some View {
        adminSection {
            VStack(alignment: .leading, spacing: 14) {
                Text("시즌 찾아오기")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                Text("브랜드의 룩북 목록 URL을 바탕으로 가져올 시즌 후보를 찾습니다.")
                    .font(.caption)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                secondaryButton(
                    title: "시즌 찾아오기 시작",
                    isDisabled: !hasLookbookArchiveURL(brand)
                ) {
                    isPresentingSeasonAddition = true
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
