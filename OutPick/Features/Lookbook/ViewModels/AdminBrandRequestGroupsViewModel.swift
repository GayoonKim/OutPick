//
//  AdminBrandRequestGroupsViewModel.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import Foundation

@MainActor
final class AdminBrandRequestGroupsViewModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    struct PendingCompletion: Identifiable, Equatable {
        let group: AdminBrandRequestGroup
        let resolvedBrandID: BrandID

        var id: String {
            "\(group.id)_\(resolvedBrandID.value)"
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var groups: [AdminBrandRequestGroup] = []
    @Published private(set) var historicalGroups: [AdminBrandRequestGroup] = []
    @Published private(set) var updatingGroupID: String?
    @Published var selectedStage: BrandRequestAdminStage = .requested
    @Published private(set) var isHistoricalGroupsVisible: Bool = false
    @Published private(set) var isLoadingHistoricalGroups: Bool = false
    @Published private(set) var isLoadingMoreHistoricalGroups: Bool = false
    @Published var pendingCompletion: PendingCompletion?
    @Published var adminNoteDraft: String = ""

    private let listUseCase: any ListBrandRequestGroupsUseCaseProtocol
    private let updateUseCase: any UpdateBrandRequestGroupStageUseCaseProtocol
    private let resolveUseCase: any ResolveBrandRequestGroupUseCaseProtocol
    private let markCreatedUseCase: any MarkBrandRequestGroupBrandCreatedUseCaseProtocol
    private let pageLimit: Int
    private let prefetchThreshold: Int
    private var nextCursor: AdminBrandRequestGroupPage.Cursor?
    private var historicalNextCursor: AdminBrandRequestGroupPage.Cursor?
    private var isLoading = false

    init(
        listUseCase: any ListBrandRequestGroupsUseCaseProtocol,
        updateUseCase: any UpdateBrandRequestGroupStageUseCaseProtocol,
        resolveUseCase: any ResolveBrandRequestGroupUseCaseProtocol,
        markCreatedUseCase: any MarkBrandRequestGroupBrandCreatedUseCaseProtocol,
        pageLimit: Int = 30,
        prefetchThreshold: Int = 6
    ) {
        self.listUseCase = listUseCase
        self.updateUseCase = updateUseCase
        self.resolveUseCase = resolveUseCase
        self.markCreatedUseCase = markCreatedUseCase
        self.pageLimit = pageLimit
        self.prefetchThreshold = prefetchThreshold
    }

    var canLoadNextPage: Bool {
        nextCursor != nil && isLoading == false
    }

    var showsHistoricalGroupsButton: Bool {
        selectedStage.isProcessed &&
            isHistoricalGroupsVisible == false &&
            isLoading == false
    }

    func loadInitial() async {
        guard phase == .idle else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        let shouldReloadHistory = selectedStage.isProcessed && isHistoricalGroupsVisible

        isLoading = true
        defer { isLoading = false }

        phase = .loading
        nextCursor = nil

        do {
            let page = try await fetchGroups(processedScope: listProcessedScope, cursor: nil)
            groups = page.groups
            nextCursor = page.nextCursor
            phase = .ready
            if shouldReloadHistory {
                await reloadHistoricalGroups()
            } else if selectedStage.isProcessed == false {
                resetHistoricalGroups()
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func selectStage(_ stage: BrandRequestAdminStage) async {
        guard selectedStage != stage else { return }
        selectedStage = stage
        resetHistoricalGroups()
        pendingCompletion = nil
        adminNoteDraft = ""
        await reload()
    }

    func loadNextPageIfNeeded(current group: AdminBrandRequestGroup) async {
        guard let nextCursor else { return }
        guard shouldPrefetch(afterSeeing: group) else { return }
        guard !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let page = try await fetchGroups(processedScope: listProcessedScope, cursor: nextCursor)
            groups.append(contentsOf: page.groups)
            self.nextCursor = page.nextCursor
            phase = .ready
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func revealHistoricalGroups() async {
        guard selectedStage.isProcessed,
              isHistoricalGroupsVisible == false
        else {
            return
        }

        isHistoricalGroupsVisible = true
        await reloadHistoricalGroups()
    }

    func loadMoreHistoricalGroupsIfNeeded(current group: AdminBrandRequestGroup) async {
        guard selectedStage.isProcessed,
              isHistoricalGroupsVisible,
              let historicalNextCursor,
              isLoadingHistoricalGroups == false,
              isLoadingMoreHistoricalGroups == false,
              shouldPrefetchHistorical(afterSeeing: group)
        else {
            return
        }

        isLoadingMoreHistoricalGroups = true
        defer { isLoadingMoreHistoricalGroups = false }

        do {
            let page = try await fetchGroups(processedScope: .history, cursor: historicalNextCursor)
            historicalGroups.append(contentsOf: historicalOnlyGroups(page.groups))
            self.historicalNextCursor = page.nextCursor
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func startProcessing(_ group: AdminBrandRequestGroup) async {
        await updateStage(
            group,
            adminStage: .processing,
            rejectionReason: nil
        )
    }

    func reject(
        _ group: AdminBrandRequestGroup,
        reason: BrandRequestRejectionReason,
        adminNote: String?
    ) async {
        await updateStage(
            group,
            adminStage: .rejected,
            rejectionReason: reason,
            adminNote: adminNote
        )
    }

    func prepareCompletion(
        group: AdminBrandRequestGroup,
        resolvedBrandID: BrandID
    ) {
        pendingCompletion = PendingCompletion(
            group: group,
            resolvedBrandID: resolvedBrandID
        )
        adminNoteDraft = ""
    }

    func cancelPendingCompletion() {
        pendingCompletion = nil
        adminNoteDraft = ""
    }

    func markBrandCreated(
        groupID: String,
        createdBrandID: BrandID
    ) async -> Bool {
        updatingGroupID = groupID
        defer { updatingGroupID = nil }

        do {
            _ = try await markCreatedUseCase.execute(
                groupID: groupID,
                createdBrandID: createdBrandID
            )
            await reload()
            return true
        } catch {
            phase = .failed(error.localizedDescription)
            return false
        }
    }

    private func updateStage(
        _ group: AdminBrandRequestGroup,
        adminStage: BrandRequestAdminStage,
        rejectionReason: BrandRequestRejectionReason?,
        adminNote: String? = nil
    ) async {
        updatingGroupID = group.id
        defer { updatingGroupID = nil }

        do {
            _ = try await updateUseCase.execute(
                groupID: group.id,
                adminStage: adminStage,
                rejectionReason: rejectionReason,
                adminNote: adminNote
            )
            adminNoteDraft = ""
            selectedStage = adminStage
            resetHistoricalGroups()
            await reload()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func confirmCompletion(_ completion: PendingCompletion) async {
        updatingGroupID = completion.group.id
        defer { updatingGroupID = nil }

        do {
            _ = try await resolveUseCase.execute(
                groupID: completion.group.id,
                resolvedBrandID: completion.resolvedBrandID,
                adminNote: nil
            )
            adminNoteDraft = ""
            await reload()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func shouldPrefetch(afterSeeing group: AdminBrandRequestGroup) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == group.id }) else {
            return false
        }
        return index >= max(groups.count - prefetchThreshold, 0)
    }

    private func shouldPrefetchHistorical(afterSeeing group: AdminBrandRequestGroup) -> Bool {
        guard let index = historicalGroups.firstIndex(where: { $0.id == group.id }) else {
            return false
        }
        return index >= max(historicalGroups.count - prefetchThreshold, 0)
    }

    private func fetchGroups(
        processedScope: ProcessedRequestScope?,
        cursor: AdminBrandRequestGroupPage.Cursor?
    ) async throws -> AdminBrandRequestGroupPage {
        try await listUseCase.execute(
            adminStage: selectedStage,
            processedScope: processedScope,
            limit: pageLimit,
            cursor: cursor
        )
    }

    private func reloadHistoricalGroups() async {
        guard selectedStage.isProcessed else {
            resetHistoricalGroups()
            return
        }

        isLoadingHistoricalGroups = true
        defer { isLoadingHistoricalGroups = false }

        do {
            let page = try await fetchGroups(processedScope: .history, cursor: nil)
            historicalGroups = historicalOnlyGroups(page.groups)
            historicalNextCursor = page.nextCursor
        } catch {
            historicalGroups = []
            historicalNextCursor = nil
            phase = .failed(error.localizedDescription)
        }
    }

    private func resetHistoricalGroups() {
        historicalGroups = []
        historicalNextCursor = nil
        isHistoricalGroupsVisible = false
        isLoadingHistoricalGroups = false
        isLoadingMoreHistoricalGroups = false
    }

    private func historicalOnlyGroups(
        _ fetchedGroups: [AdminBrandRequestGroup]
    ) -> [AdminBrandRequestGroup] {
        let recentIDs = Set(groups.map(\.id))
        let existingHistoryIDs = Set(historicalGroups.map(\.id))
        return fetchedGroups.filter { group in
            recentIDs.contains(group.id) == false &&
                existingHistoryIDs.contains(group.id) == false
        }
    }

    private var listProcessedScope: ProcessedRequestScope? {
        selectedStage.isProcessed ? .recent : nil
    }
}
