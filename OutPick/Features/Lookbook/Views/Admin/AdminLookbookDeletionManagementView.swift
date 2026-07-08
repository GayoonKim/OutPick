//
//  AdminLookbookDeletionManagementView.swift
//  OutPick
//
//  Created by Codex on 7/7/26.
//

import SwiftUI

struct AdminLookbookDeletionManagementView: View {
    @StateObject private var viewModel: AdminLookbookDeletionManagementViewModel
    private let coordinator: LookbookCoordinator
    private let brandImageCache: any BrandImageCacheProtocol
    private let showsNavigationBar: Bool
    private let allowsDeletionSelection: Bool

    @EnvironmentObject private var brandAdminSessionStore: BrandAdminSessionStore
    @State private var prefetchedPostImagePaths: Set<String> = []
    @State private var expandedRequestBrandIDs: Set<BrandID> = []

    private let postColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(
        viewModel: AdminLookbookDeletionManagementViewModel,
        coordinator: LookbookCoordinator,
        brandImageCache: any BrandImageCacheProtocol,
        showsNavigationBar: Bool = true,
        allowsDeletionSelection: Bool = true
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coordinator = coordinator
        self.brandImageCache = brandImageCache
        self.showsNavigationBar = showsNavigationBar
        self.allowsDeletionSelection = allowsDeletionSelection
    }

    var body: some View {
        content
            .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
            .conditionalLookbookNavigationBar(
                isVisible: showsNavigationBar,
                title: allowsDeletionSelection ? "삭제 관리" : "삭제 요청 목록",
                onBack: { coordinator.pop() }
            )
            .task {
                await brandAdminSessionStore.ensureWritableBrandsLoaded()
                await viewModel.loadInitialContent(isTotalAdmin: brandAdminSessionStore.isTotalAdmin)
                if allowsDeletionSelection == false {
                    await viewModel.selectTab(.requests, isTotalAdmin: brandAdminSessionStore.isTotalAdmin)
                }
            }
            .refreshable {
                await viewModel.loadInitialContent(isTotalAdmin: brandAdminSessionStore.isTotalAdmin)
            }
            .onChange(of: viewModel.message) { newValue in
                viewModel.scheduleMessageAutoDismissIfNeeded(newValue)
            }
            .onChange(of: viewModel.expandedSeason?.id) { _ in
                prefetchedPostImagePaths.removeAll()
                prefetchInitialPostImages()
            }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if allowsDeletionSelection {
                    tabPicker
                }

                if allowsDeletionSelection == false {
                    deletionRequestsSection
                } else {
                    switch viewModel.selectedTab {
                    case .selection:
                        deletionSelectionContent
                    case .requests:
                        deletionRequestsSection
                    }
                }

                if let message = viewModel.message {
                    feedbackMessage(message)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 40)
        }
    }

    private var tabPicker: some View {
        Picker("삭제 관리 탭", selection: tabBinding) {
            ForEach(AdminLookbookDeletionManagementTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    private var tabBinding: Binding<AdminLookbookDeletionManagementTab> {
        Binding(
            get: { viewModel.selectedTab },
            set: { tab in
                Task {
                    await viewModel.selectTab(
                        tab,
                        isTotalAdmin: brandAdminSessionStore.isTotalAdmin
                    )
                }
            }
        )
    }

    @ViewBuilder
    private var deletionSelectionContent: some View {
        if viewModel.shouldShowBrandSearch {
            brandSelectionSection
        }

        if brandAdminSessionStore.isTotalAdmin, viewModel.selectedBrand != nil {
            brandDeletionSection
        }

        if viewModel.selectedBrand != nil {
            contentDeletionSection
        } else {
            adminSection {
                emptyText("삭제 관리할 브랜드를 선택해주세요.")
            }
        }
    }

    private var brandSelectionSection: some View {
        adminSection {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader(
                    title: "브랜드",
                    subtitle: viewModel.shouldShowBrandSearch ?
                        "삭제 탭에서만 브랜드를 검색하고 선택합니다." :
                        nil
                )

                if let selectedBrand = viewModel.selectedBrand {
                    selectedBrandRow(selectedBrand)
                }

                if viewModel.shouldShowBrandSearch {
                    searchField

                    ForEach(visibleSearchResults) { brand in
                        Button {
                            Task {
                                await viewModel.selectBrand(
                                    brand,
                                    isTotalAdmin: brandAdminSessionStore.isTotalAdmin
                                )
                            }
                        } label: {
                            brandRow(brand)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var brandDeletionSection: some View {
        adminSection {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "브랜드 삭제 요청",
                    subtitle: "총 관리자만 브랜드 삭제 요청을 만들 수 있습니다. 요청 후 사용자 화면에서는 즉시 숨겨집니다."
                )

                reasonField

                destructiveButton(
                    title: "브랜드 삭제 요청",
                    isLoading: viewModel.mutationKey?.hasPrefix("brand:") == true,
                    isDisabled: viewModel.mutationKey != nil
                ) {
                    Task {
                        await viewModel.requestBrandDeletion(
                            isTotalAdmin: brandAdminSessionStore.isTotalAdmin
                        )
                    }
                }
            }
        }
    }

    private var contentDeletionSection: some View {
        adminSection {
            VStack(alignment: .leading, spacing: 16) {
                sectionHeader(
                    title: "시즌 / 포스트 삭제",
                    subtitle: "시즌은 가로 카드에서 선택하고, 포스트는 선택한 시즌의 이미지 grid에서 선택합니다."
                )

                reasonField

                seasonSelectionSection

                if let expandedSeason = viewModel.expandedSeason {
                    Divider()
                        .background(OutPickTheme.SwiftUIColor.borderSubtle)
                    postSelectionSection(expandedSeason)
                }
            }
        }
    }

    @ViewBuilder
    private var seasonSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("시즌")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

                Spacer()

                if viewModel.selectedSeasonIDs.isEmpty == false {
                    Text("\(viewModel.selectedSeasonIDs.count)개 선택")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
                }
            }

            if viewModel.isLoadingBrandContent {
                loadingRow("시즌을 불러오는 중입니다.")
            } else if viewModel.seasons.isEmpty {
                emptyText("삭제할 수 있는 시즌이 없습니다.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.seasons) { season in
                            seasonCard(season)
                        }
                    }
                    .padding(.vertical, 2)
                }

                destructiveButton(
                    title: "선택한 시즌 \(viewModel.selectedSeasonIDs.count)개 삭제 요청",
                    isLoading: viewModel.mutationKey == "batch:seasons",
                    isDisabled: viewModel.mutationKey != nil || viewModel.selectedSeasonIDs.isEmpty
                ) {
                    Task {
                        await viewModel.softDeleteSelectedSeasons(
                            isTotalAdmin: brandAdminSessionStore.isTotalAdmin
                        )
                    }
                }
            }
        }
    }

    private func postSelectionSection(_ season: Season) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(season.title) 포스트")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .lineLimit(1)

                Spacer()

                if viewModel.selectedPostIDs.isEmpty == false {
                    Text("\(viewModel.selectedPostIDs.count)개 선택")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
                }
            }

            if viewModel.isLoadingPosts {
                loadingRow("포스트를 불러오는 중입니다.")
            } else if viewModel.posts.isEmpty {
                emptyText("삭제할 수 있는 포스트가 없습니다.")
            } else {
                LazyVGrid(columns: postColumns, spacing: 10) {
                    ForEach(viewModel.posts) { post in
                        postGridCell(post)
                            .onAppear {
                                Task {
                                    await viewModel.loadMorePostsIfNeeded(currentPostID: post.id)
                                }
                                prefetchPostImages(around: post.id)
                            }
                    }
                }

                if viewModel.isLoadingMorePosts {
                    loadingRow("포스트를 더 불러오는 중입니다.")
                }

                destructiveButton(
                    title: "선택한 포스트 \(viewModel.selectedPostIDs.count)개 삭제 요청",
                    isLoading: viewModel.mutationKey == "batch:posts",
                    isDisabled: viewModel.mutationKey != nil || viewModel.selectedPostIDs.isEmpty
                ) {
                    Task {
                        await viewModel.softDeleteSelectedPosts(
                            isTotalAdmin: brandAdminSessionStore.isTotalAdmin
                        )
                    }
                }
            }
        }
    }

    private var deletionRequestsSection: some View {
        adminSection {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader(
                    title: "삭제 요청 목록",
                    subtitle: requestListSubtitle
                )

                if viewModel.isLoadingRequests {
                    loadingRow("삭제 요청을 불러오는 중입니다.")
                } else if viewModel.deletionRequests.isEmpty {
                    emptyText("진행 중인 삭제 요청이 없습니다.")
                } else if allowsDeletionSelection == false,
                          brandAdminSessionStore.isTotalAdmin,
                          viewModel.selectedBrand == nil {
                    globalDeletionRequestGroups
                } else {
                    ForEach(viewModel.deletionRequests) { request in
                        deletionRequestRow(request)
                    }
                }
            }
        }
    }

    private var globalDeletionRequestGroups: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groupedDeletionRequests) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        toggleExpandedBrand(group.brandID)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.title)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                                    .lineLimit(1)
                                Text(groupSummary(group.requests))
                                    .font(.caption)
                                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                            }

                            Spacer()

                            Text(expandedRequestBrandIDs.contains(group.brandID) ? "닫기" : "보기")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(OutPickTheme.SwiftUIColor.surfaceBase)
                                .clipShape(Capsule())
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if expandedRequestBrandIDs.contains(group.brandID) {
                        groupedTargetSection(type: .brand, requests: group.requests.filter { $0.targetType == .brand })
                        groupedTargetSection(type: .season, requests: group.requests.filter { $0.targetType == .season })
                        groupedTargetSection(type: .post, requests: group.requests.filter { $0.targetType == .post })
                    }
                }
                .padding(12)
                .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func groupedTargetSection(
        type: LookbookDeletionTargetType,
        requests: [LookbookDeletionRequest]
    ) -> some View {
        if requests.isEmpty == false {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text(type.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                    Spacer()

                    Text("\(requests.count)건")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                        .clipShape(Capsule())
                }

                ForEach(requests) { request in
                    deletionRequestRow(request)
                }
            }
            .padding(12)
            .background(OutPickTheme.SwiftUIColor.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.top, 6)
        }
    }

    private var requestListSubtitle: String {
        if brandAdminSessionStore.isTotalAdmin, viewModel.selectedBrand == nil {
            return "전체 활성 삭제 요청을 확인합니다."
        }
        return "현재 브랜드의 활성 삭제 요청을 확인합니다."
    }

    private var groupedDeletionRequests: [DeletionRequestBrandGroup] {
        let grouped = Dictionary(grouping: viewModel.deletionRequests, by: \.brandID)
        let groups = grouped.map { brandID, requests in
            makeDeletionRequestBrandGroup(
                brandID: brandID,
                requests: requests
            )
        }
        return groups.sorted { $0.sortDate > $1.sortDate }
    }

    private func makeDeletionRequestBrandGroup(
        brandID: BrandID,
        requests: [LookbookDeletionRequest]
    ) -> DeletionRequestBrandGroup {
        let sortedRequests = requests.sorted {
            deletionRequestSortDate($0) > deletionRequestSortDate($1)
        }
        return DeletionRequestBrandGroup(
            brandID: brandID,
            title: sortedRequests.compactMap(\.brandName).first ?? "삭제된 브랜드",
            requests: sortedRequests,
            sortDate: sortedRequests.first.map(deletionRequestSortDate) ?? .distantPast
        )
    }

    private func deletionRequestSortDate(_ request: LookbookDeletionRequest) -> Date {
        request.updatedAt ?? request.requestedAt ?? .distantPast
    }

    private func groupSummary(_ requests: [LookbookDeletionRequest]) -> String {
        let brandCount = requests.filter { $0.targetType == .brand }.count
        let seasonCount = requests.filter { $0.targetType == .season }.count
        let postCount = requests.filter { $0.targetType == .post }.count
        return "총 \(requests.count)건 · 브랜드 \(brandCount) · 시즌 \(seasonCount) · 포스트 \(postCount)"
    }

    private func toggleExpandedBrand(_ brandID: BrandID) {
        if expandedRequestBrandIDs.contains(brandID) {
            expandedRequestBrandIDs.remove(brandID)
        } else {
            expandedRequestBrandIDs.insert(brandID)
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

    private var reasonField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("삭제 사유")
                .font(.caption.weight(.semibold))
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

            TextField("선택 입력", text: $viewModel.reasonText)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func selectedBrandRow(_ brand: Brand) -> some View {
        HStack(spacing: 12) {
            brandLogo(brand)

            VStack(alignment: .leading, spacing: 4) {
                Text(brand.name)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    .lineLimit(1)
                if let englishName = brand.englishName, englishName.isEmpty == false {
                    Text(englishName)
                        .font(.caption)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if viewModel.canClearSelectedBrand {
                Button {
                    Task {
                        await viewModel.clearSelectedBrand(
                            isTotalAdmin: brandAdminSessionStore.isTotalAdmin
                        )
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.iconSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("선택 브랜드 지우기")
            }
        }
        .padding(12)
        .background(OutPickTheme.SwiftUIColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func brandRow(_ brand: Brand) -> some View {
        HStack(spacing: 12) {
            brandLogo(brand)

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

    private func brandLogo(_ brand: Brand) -> some View {
        LookbookAssetImageView(
            primaryPath: brand.logoThumbPath,
            secondaryPath: brand.logoDetailPath ?? brand.logoOriginalPath,
            remoteURL: nil,
            sourcePageURL: nil,
            brandImageCache: brandImageCache,
            maxBytes: 800_000
        )
        .frame(width: 42, height: 42)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func seasonCard(_ season: Season) -> some View {
        let isSelected = viewModel.isSeasonSelected(season)
        let isExpanded = viewModel.expandedSeason?.id == season.id

        return ZStack(alignment: .topTrailing) {
            Button {
                Task {
                    await viewModel.toggleExpandedSeason(season)
                }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    LookbookAssetImageView(
                        primaryPath: season.coverThumbPath,
                        secondaryPath: season.coverPath,
                        remoteURL: season.coverRemoteURL.flatMap(URL.init(string:)),
                        sourcePageURL: season.sourceURL.flatMap(URL.init(string:)),
                        brandImageCache: brandImageCache,
                        maxBytes: 900_000
                    )
                    .frame(width: 136, height: 156)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text(season.title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .lineLimit(1)

                    Text("\(season.postCount)개 포스트")
                        .font(.caption2)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: 136, alignment: .leading)
                .padding(10)
                .background(rowBackground(isSelected: isExpanded))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isExpanded ?
                                OutPickTheme.SwiftUIColor.accent :
                                OutPickTheme.SwiftUIColor.borderSubtle,
                            lineWidth: isExpanded ? 1.5 : 1
                        )
                )
            }
            .buttonStyle(.plain)

            Button {
                viewModel.toggleSeasonSelection(season)
            } label: {
                selectionBadge(isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .padding(16)
            .accessibilityLabel(isSelected ? "시즌 선택 해제" : "시즌 선택")
        }
    }

    private func postGridCell(_ post: LookbookPost) -> some View {
        let isSelected = viewModel.isPostSelected(post)
        let media = post.media.first

        return Button {
            viewModel.togglePostSelection(post)
        } label: {
            ZStack(alignment: .topTrailing) {
                LookbookAssetImageView(
                    primaryPath: media?.preferredListPath,
                    secondaryPath: media?.preferredDetailPath,
                    remoteURL: media?.remoteURL,
                    sourcePageURL: media?.sourcePageURL,
                    brandImageCache: brandImageCache,
                    maxBytes: 900_000
                )
                .aspectRatio(0.78, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected ?
                                OutPickTheme.SwiftUIColor.accent :
                                OutPickTheme.SwiftUIColor.borderSubtle,
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                if isSelected {
                    Color.black.opacity(0.22)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                selectionBadge(isSelected: isSelected)
                    .padding(8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "포스트 선택 해제" : "포스트 선택")
    }

    private func deletionRequestRow(_ request: LookbookDeletionRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                deletionRequestImage(request)

                VStack(alignment: .leading, spacing: 4) {
                    Text(requestDisplayTitle(request))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .lineLimit(2)
                    Text("\(request.targetType.title) 삭제 요청")
                        .font(.caption)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    if let restoreUntil = request.restoreUntil {
                        Text("복구 가능: \(formatDate(restoreUntil))")
                            .font(.caption)
                            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    }
                }

                Spacer()

                Text(request.status.title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
            }

            if let reason = request.reason, reason.isEmpty == false {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .lineLimit(3)
            }

            HStack(spacing: 10) {
                if brandAdminSessionStore.isTotalAdmin, request.targetType == .brand {
                    secondaryInlineButton(
                        title: "복구",
                        isLoading: viewModel.mutationKey == "request:\(request.requestID)"
                    ) {
                        Task {
                            await viewModel.cancelBrandDeletion(
                                request,
                                isTotalAdmin: brandAdminSessionStore.isTotalAdmin
                            )
                        }
                    }
                } else if request.targetType != .brand {
                    secondaryInlineButton(
                        title: "복구",
                        isLoading: viewModel.mutationKey == "request:\(request.requestID)"
                    ) {
                        Task {
                            await viewModel.restore(
                                request,
                                isTotalAdmin: brandAdminSessionStore.isTotalAdmin
                            )
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(OutPickTheme.SwiftUIColor.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func deletionRequestImage(_ request: LookbookDeletionRequest) -> some View {
        LookbookAssetImageView(
            primaryPath: request.targetImagePath ?? fallbackImagePath(request),
            secondaryPath: fallbackImagePath(request),
            remoteURL: nil,
            sourcePageURL: nil,
            brandImageCache: brandImageCache,
            maxBytes: 800_000
        )
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func selectionBadge(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(
                isSelected ?
                    OutPickTheme.SwiftUIColor.accent :
                    OutPickTheme.SwiftUIColor.iconSecondary
            )
            .background(
                Circle()
                    .fill(OutPickTheme.SwiftUIColor.backgroundBase.opacity(0.82))
            )
    }

    private func sectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
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

    private func destructiveButton(
        title: String,
        isLoading: Bool,
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
            .background(OutPickTheme.SwiftUIColor.destructive)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(isDisabled ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func secondaryInlineButton(
        title: String,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            inlineButtonLabel(title: title, isLoading: isLoading)
                .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.mutationKey != nil)
    }

    private func inlineButtonLabel(title: String, isLoading: Bool) -> some View {
        Group {
            if isLoading {
                ProgressView()
                    .tint(OutPickTheme.SwiftUIColor.accent)
            } else {
                Text(title)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(OutPickTheme.SwiftUIColor.surfaceBase)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func loadingRow(_ text: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)
            Text(text)
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private func emptyText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    private func feedbackMessage(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OutPickTheme.SwiftUIColor.warning.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func rowBackground(isSelected: Bool) -> Color {
        isSelected ?
            OutPickTheme.SwiftUIColor.accent.opacity(0.14) :
            OutPickTheme.SwiftUIColor.surfaceElevated
    }

    private func requestDisplayTitle(_ request: LookbookDeletionRequest) -> String {
        if request.targetType == .season,
           let seasonTitle = request.seasonTitle,
           seasonTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return seasonTitle
        }

        if let displayName = request.targetDisplayName,
           displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return displayName
        }
        switch request.targetType {
        case .brand:
            return request.brandName ?? "삭제된 브랜드"
        case .season:
            return request.seasonTitle ?? "삭제된 시즌"
        case .post:
            return request.postCaption ?? "삭제된 포스트"
        }
    }

    private func fallbackImagePath(_ request: LookbookDeletionRequest) -> String? {
        switch request.targetType {
        case .brand:
            return request.brandLogoThumbPath
        case .season:
            return request.seasonCoverThumbPath
        case .post:
            return request.postImageThumbPath
        }
    }

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private var visibleSearchResults: [Brand] {
        guard brandAdminSessionStore.isTotalAdmin == false else {
            return viewModel.searchResults
        }

        return viewModel.searchResults.filter { brand in
            brandAdminSessionStore.canWrite(brandID: brand.id)
        }
    }

    private func prefetchInitialPostImages() {
        prefetchPostImages(from: Array(viewModel.posts.prefix(8)))
    }

    private func prefetchPostImages(around postID: PostID) {
        guard let index = viewModel.posts.firstIndex(where: { $0.id == postID }) else { return }
        let upperBound = min(viewModel.posts.count, index + 8)
        prefetchPostImages(from: Array(viewModel.posts[index..<upperBound]))
    }

    private func prefetchPostImages(from posts: [LookbookPost]) {
        let items = posts.compactMap { post -> (path: String, maxBytes: Int)? in
            guard let path = post.media.first?.preferredListPath,
                  prefetchedPostImagePaths.contains(path) == false else {
                return nil
            }
            return (path: path, maxBytes: 900_000)
        }
        guard items.isEmpty == false else { return }
        prefetchedPostImagePaths.formUnion(items.map(\.path))
        Task {
            await brandImageCache.prefetch(items: items, concurrency: 4)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct DeletionRequestBrandGroup: Identifiable {
    let brandID: BrandID
    let title: String
    let requests: [LookbookDeletionRequest]
    let sortDate: Date

    var id: BrandID { brandID }
}

private extension View {
    @ViewBuilder
    func conditionalLookbookNavigationBar(
        isVisible: Bool,
        title: String,
        onBack: @escaping () -> Void
    ) -> some View {
        if isVisible {
            lookbookNavigationBar(
                title: title,
                showsBackButton: true,
                onBack: onBack
            )
        } else {
            self
        }
    }
}
