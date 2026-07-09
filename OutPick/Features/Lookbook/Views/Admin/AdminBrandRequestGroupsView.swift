//
//  AdminBrandRequestGroupsView.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import SwiftUI

struct AdminBrandRequestGroupsView: View {
    @StateObject private var viewModel: AdminBrandRequestGroupsViewModel
    private let createBrandFlowFactory: (String?, String?, @escaping (Brand.ID) -> Void) -> AnyView
    private let coordinator: LookbookCoordinator

    @State private var processingTarget: AdminBrandRequestGroup?
    @State private var rejectionTarget: AdminBrandRequestGroup?
    @State private var brandCreationDraft: BrandCreationDraft?
    @State private var activeBrandCreationGroupID: String?
    @State private var createdBrandID: Brand.ID?
    @State private var createdBrandIDsByGroupID: [String: Brand.ID] = [:]

    init(
        viewModel: AdminBrandRequestGroupsViewModel,
        createBrandFlowFactory: @escaping (String?, String?, @escaping (Brand.ID) -> Void) -> AnyView,
        coordinator: LookbookCoordinator
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.createBrandFlowFactory = createBrandFlowFactory
        self.coordinator = coordinator
    }

    var body: some View {
        VStack(spacing: 0) {
            stagePicker
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            content
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .lookbookNavigationBar(
            title: "브랜드 요청",
            showsBackButton: true,
            onBack: { coordinator.pop() }
        )
        .task {
            await viewModel.loadInitial()
        }
        .sheet(item: $rejectionTarget) { group in
            RejectionReasonSheet(
                group: group,
                onCancel: {
                    rejectionTarget = nil
                },
                onConfirm: { reason, adminNote in
                    rejectionTarget = nil
                    Task {
                        await viewModel.reject(
                            group,
                            reason: reason,
                            adminNote: adminNote
                        )
                    }
                }
            )
        }
        .overlay { statusChangeConfirmationOverlay }
        .fullScreenCover(item: $brandCreationDraft, onDismiss: {
            guard let activeBrandCreationGroupID, let createdBrandID else {
                self.activeBrandCreationGroupID = nil
                self.createdBrandID = nil
                return
            }
            let createdGroupID = activeBrandCreationGroupID
            createdBrandIDsByGroupID[createdGroupID] = createdBrandID
            self.activeBrandCreationGroupID = nil
            self.createdBrandID = nil
            Task {
                let didPersist = await viewModel.markBrandCreated(
                    groupID: createdGroupID,
                    createdBrandID: createdBrandID
                )
                guard didPersist else { return }
                coordinator.pushAdminBrandManagement(initialBrandID: createdBrandID)
            }
        }) { draft in
            NavigationView {
                createBrandFlowFactory(
                    draft.brandName,
                    draft.englishName
                ) { createdBrandID in
                    self.createdBrandID = createdBrandID
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
        }
    }

    private var stagePicker: some View {
        Picker("요청 상태", selection: Binding(
            get: { viewModel.selectedStage },
            set: { stage in
                Task { await viewModel.selectStage(stage) }
            }
        )) {
            Text("새 요청").tag(BrandRequestAdminStage.requested)
            Text("처리 중").tag(BrandRequestAdminStage.processing)
            Text("보류").tag(BrandRequestAdminStage.rejected)
            Text("완료").tag(BrandRequestAdminStage.completed)
        }
        .pickerStyle(.segmented)
        .tint(OutPickTheme.SwiftUIColor.accent)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            Spacer()
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)
            Spacer()

        case .failed(let message):
            Spacer()
            VStack(spacing: 12) {
                Text("요청 그룹을 불러오지 못했어요")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .multilineTextAlignment(.center)
                Button("다시 시도") {
                    Task { await viewModel.reload() }
                }
                .tint(OutPickTheme.SwiftUIColor.accent)
            }
            .padding(.horizontal, 24)
            Spacer()

        case .ready:
            if viewModel.groups.isEmpty, viewModel.selectedStage.isProcessed == false {
                emptyState
            } else {
                groupList
            }
        }
    }

    private var groupList: some View {
        List {
            if viewModel.groups.isEmpty {
                emptyListRow(title: emptyTitle, subtitle: emptySubtitle)
            } else {
                ForEach(viewModel.groups) { group in
                    groupRow(group, allowsHistoricalPrefetch: false)
                        .onAppear {
                            Task {
                                await viewModel.loadNextPageIfNeeded(current: group)
                            }
                        }
                }
            }

            if viewModel.selectedStage.isProcessed {
                historicalGroupsSection
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.reload()
        }
    }

    @ViewBuilder
    private var historicalGroupsSection: some View {
        if viewModel.isHistoricalGroupsVisible {
            Section {
                if viewModel.isLoadingHistoricalGroups {
                    loadingListRow("이전 기록을 불러오는 중입니다.")
                } else if viewModel.historicalGroups.isEmpty {
                    emptyListRow(
                        title: historicalEmptyTitle,
                        subtitle: "14일 이전 처리 이력이 없어요."
                    )
                } else {
                    ForEach(viewModel.historicalGroups) { group in
                        groupRow(group, allowsHistoricalPrefetch: true)
                    }
                }

                if viewModel.isLoadingMoreHistoricalGroups {
                    loadingListRow("이전 기록을 더 불러오는 중입니다.")
                }
            } header: {
                Text(historicalSectionTitle)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .textCase(nil)
                    .padding(.top, 8)
            }
        } else if viewModel.showsHistoricalGroupsButton {
            Button {
                Task {
                    await viewModel.revealHistoricalGroups()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                    Text(historicalButtonTitle)
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(OutPickTheme.SwiftUIColor.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .listRowBackground(OutPickTheme.SwiftUIColor.backgroundBase)
        }
    }

    private func groupRow(
        _ group: AdminBrandRequestGroup,
        allowsHistoricalPrefetch: Bool
    ) -> some View {
        AdminBrandRequestGroupRowView(
            group: group,
            isUpdating: viewModel.updatingGroupID == group.id,
            actions: AdminBrandRequestGroupRowView.Actions(
                startProcessing: {
                    processingTarget = group
                },
                reject: {
                    rejectionTarget = group
                },
                createBrand: {
                    activeBrandCreationGroupID = group.id
                    brandCreationDraft = BrandCreationDraft(group: group)
                },
                completeAfterReview: resolvedBrandID(for: group).map { brandID in
                    {
                        viewModel.prepareCompletion(
                            group: group,
                            resolvedBrandID: brandID
                        )
                    }
                }
            )
        )
        .listRowBackground(OutPickTheme.SwiftUIColor.backgroundBase)
        .onAppear {
            guard allowsHistoricalPrefetch else { return }
            Task {
                await viewModel.loadMoreHistoricalGroupsIfNeeded(current: group)
            }
        }
    }

    private func loadingListRow(_ message: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)
            Text(message)
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 18)
        .listRowBackground(OutPickTheme.SwiftUIColor.backgroundBase)
    }

    private func emptyListRow(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .listRowBackground(OutPickTheme.SwiftUIColor.backgroundBase)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            Text(emptySubtitle)
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    private var emptyTitle: String {
        switch viewModel.selectedStage {
        case .requested:
            return "새 요청이 없어요"
        case .processing:
            return "처리 중인 요청이 없어요"
        case .rejected:
            return "최근 14일 내 보류된 요청이 없어요"
        case .completed:
            return "최근 14일 내 완료된 요청이 없어요"
        }
    }

    private var emptySubtitle: String {
        switch viewModel.selectedStage {
        case .requested, .processing:
            return "상태를 바꾸면 이 목록에서 자동으로 이동해요."
        case .rejected, .completed:
            return "최근 처리 이력만 표시하고 있어요."
        }
    }

    private var historicalSectionTitle: String {
        switch viewModel.selectedStage {
        case .rejected:
            return "이전 보류 기록"
        case .completed:
            return "이전 완료 기록"
        case .requested, .processing:
            return ""
        }
    }

    private var historicalButtonTitle: String {
        "\(historicalSectionTitle) 보기"
    }

    private var historicalEmptyTitle: String {
        switch viewModel.selectedStage {
        case .rejected:
            return "이전 보류 요청이 없어요"
        case .completed:
            return "이전 완료 요청이 없어요"
        case .requested, .processing:
            return ""
        }
    }

    private func completionConfirmMessage(
        for pending: AdminBrandRequestGroupsViewModel.PendingCompletion
    ) -> String {
        "\(pending.group.displayNameSnapshot) 요청을 완료 처리할까요? 작업 결과를 직접 확인한 뒤에만 완료 처리해주세요."
    }

    @ViewBuilder
    private var statusChangeConfirmationOverlay: some View {
        if let processingTarget {
            StatusChangeConfirmationDialog(
                title: "상태 변경",
                message: "\(processingTarget.displayNameSnapshot) 요청을 처리 중으로 변경할까요?",
                onCancel: {
                    self.processingTarget = nil
                },
                onConfirm: {
                    let group = processingTarget
                    self.processingTarget = nil
                    Task {
                        await viewModel.startProcessing(group)
                    }
                }
            )
        } else if let pending = viewModel.pendingCompletion {
            StatusChangeConfirmationDialog(
                title: "상태 변경",
                message: completionConfirmMessage(for: pending),
                onCancel: {
                    viewModel.cancelPendingCompletion()
                },
                onConfirm: {
                    viewModel.cancelPendingCompletion()
                    Task {
                        await viewModel.confirmCompletion(pending)
                    }
                }
            )
        }
    }

    private func resolvedBrandID(for group: AdminBrandRequestGroup) -> Brand.ID? {
        group.resolvedBrandID ?? group.createdBrandID ?? createdBrandIDsByGroupID[group.id]
    }
}

private struct RejectionReasonSheet: View {
    let group: AdminBrandRequestGroup
    let onCancel: () -> Void
    let onConfirm: (BrandRequestRejectionReason, String?) -> Void

    @State private var selectedReason: BrandRequestRejectionReason = .unavailable
    @State private var adminNote: String = ""

    private var trimmedAdminNote: String {
        adminNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var noteEditorHeight: CGFloat {
        let lineCount = max(adminNote.components(separatedBy: .newlines).count, 1)
        let wrappedLineEstimate = max(adminNote.count / 28, 0)
        let estimatedLines = max(lineCount, wrappedLineEstimate + 1)
        return min(max(CGFloat(estimatedLines) * 22 + 24, 56), 116)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("보류 사유")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                Text("\(group.displayNameSnapshot) 요청을 보류 상태로 변경합니다.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                ForEach(BrandRequestRejectionReason.allCases, id: \.self) { reason in
                    Button {
                        selectedReason = reason
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(reason.pointColor)
                                .frame(width: 10, height: 10)

                            Text(reason.displayTitle)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                            Spacer()

                            if selectedReason == reason {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(reason.pointColor)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .background(
                            selectedReason == reason ?
                                reason.pointColor.opacity(0.18) :
                                OutPickTheme.SwiftUIColor.surfaceBase
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    selectedReason == reason ?
                                        reason.pointColor :
                                        OutPickTheme.SwiftUIColor.borderSubtle,
                                    lineWidth: 1
                                )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            if selectedReason == .other {
                VStack(alignment: .leading, spacing: 8) {
                    Text("메모")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

                    TextEditor(text: $adminNote)
                        .font(.system(size: 15))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .adminScrollContentBackgroundHiddenIfAvailable()
                        .frame(height: noteEditorHeight)
                        .padding(8)
                        .background(OutPickTheme.SwiftUIColor.surfaceBase)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("취소")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .background(OutPickTheme.SwiftUIColor.destructive)
                .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    onConfirm(
                        selectedReason,
                        trimmedAdminNote.isEmpty ? nil : trimmedAdminNote
                    )
                } label: {
                    Text("확인")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .background(OutPickTheme.SwiftUIColor.surfacePressed)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(20)
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
    }
}

private struct BrandCreationDraft: Identifiable {
    let id: String
    let brandName: String?
    let englishName: String?

    init(group: AdminBrandRequestGroup) {
        id = group.id
        brandName = Self.nonEmpty(group.displayNameSnapshot)
        englishName = Self.nonEmpty(group.englishBrandName)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct StatusChangeConfirmationDialog: View {
    let title: String
    let message: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            OutPickTheme.SwiftUIColor.overlayScrim
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                    Text(message)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("취소")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .background(OutPickTheme.SwiftUIColor.destructive)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button(action: onConfirm) {
                        Text("확인")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .background(OutPickTheme.SwiftUIColor.surfacePressed)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(20)
            .frame(maxWidth: 340)
            .background(OutPickTheme.SwiftUIColor.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
            )
            .padding(.horizontal, 24)
        }
    }
}

private extension BrandRequestRejectionReason {
    var pointColor: Color {
        switch self {
        case .unavailable:
            return OutPickTheme.SwiftUIColor.warning
        case .spam:
            return OutPickTheme.SwiftUIColor.destructive
        case .other:
            return OutPickTheme.SwiftUIColor.accent
        }
    }
}

private extension View {
    @ViewBuilder
    func adminScrollContentBackgroundHiddenIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}

private struct AdminBrandRequestGroupRowView: View {
    struct Actions {
        let startProcessing: () -> Void
        let reject: () -> Void
        let createBrand: () -> Void
        let completeAfterReview: (() -> Void)?
    }

    let group: AdminBrandRequestGroup
    let isUpdating: Bool
    let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.displayNameSnapshot)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .lineLimit(2)

                    if let englishBrandName = group.englishBrandName {
                        Text(englishBrandName)
                            .font(.footnote)
                            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                Text("\(group.requestCount)명")
                    .font(.caption)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            metaSection

            if let adminNote = group.adminNote, !adminNote.isEmpty {
                Text(adminNote)
                    .font(.caption)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textTertiary)
                    .lineLimit(2)
            }

            actionSection
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var metaSection: some View {
        HStack(spacing: 8) {
            if let rejectionReason = group.rejectionReason {
                label(rejectionReason.displayTitle)
            }

            if let updatedAt = group.updatedAt {
                Text(Self.dateFormatter.string(from: updatedAt))
                    .font(.caption)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var actionSection: some View {
        if isUpdating {
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)
        } else if group.adminStage == .completed {
            EmptyView()
        } else if group.adminStage == .processing {
            Menu {
                Button("보류", role: .destructive, action: actions.reject)

                if actions.completeAfterReview != nil {
                    Button("검수 후 완료 처리") {
                        actions.completeAfterReview?()
                    }
                } else {
                    Button("브랜드 생성", action: actions.createBrand)
                }
            } label: {
                Label("상태 변경", systemImage: "slider.horizontal.3")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(OutPickTheme.SwiftUIColor.accent)
        } else {
            Menu {
                if group.adminStage != .processing {
                    Button("처리 시작", action: actions.startProcessing)
                }

                if group.adminStage != .rejected {
                    Button("보류", role: .destructive, action: actions.reject)
                }
            } label: {
                Label("상태 변경", systemImage: "slider.horizontal.3")
                    .font(.footnote.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .tint(OutPickTheme.SwiftUIColor.accent)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(OutPickTheme.SwiftUIColor.surfaceElevated)
            .clipShape(Capsule())
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
