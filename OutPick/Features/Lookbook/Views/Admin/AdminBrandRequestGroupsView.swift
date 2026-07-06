//
//  AdminBrandRequestGroupsView.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import SwiftUI

struct AdminBrandRequestGroupsView: View {
    @StateObject private var viewModel: AdminBrandRequestGroupsViewModel
    private let createBrandFlowFactory: (@escaping (Brand.ID) -> Void) -> AnyView
    private let coordinator: LookbookCoordinator

    @State private var processingTarget: AdminBrandRequestGroup?
    @State private var rejectionTarget: AdminBrandRequestGroup?
    @State private var rejectionConfirmation: RejectionConfirmation?
    @State private var completionTarget: AdminBrandRequestGroup?
    @State private var createdBrandID: Brand.ID?
    @State private var isPresentingCreateBrand = false

    init(
        viewModel: AdminBrandRequestGroupsViewModel,
        createBrandFlowFactory: @escaping (@escaping (Brand.ID) -> Void) -> AnyView,
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
        .confirmationDialog(
            "보류 이유를 선택해주세요",
            isPresented: Binding(
                get: { rejectionTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        rejectionTarget = nil
                    }
                }
            ),
            presenting: rejectionTarget
        ) { group in
            ForEach(BrandRequestRejectionReason.allCases, id: \.self) { reason in
                Button(reason.displayTitle) {
                    rejectionTarget = nil
                    rejectionConfirmation = RejectionConfirmation(
                        group: group,
                        reason: reason
                    )
                }
            }
            Button("취소", role: .cancel) {
                rejectionTarget = nil
            }
        }
        .alert(
            "보류",
            isPresented: Binding(
                get: { rejectionConfirmation != nil },
                set: { isPresented in
                    if !isPresented {
                        rejectionConfirmation = nil
                    }
                }
            ),
            presenting: rejectionConfirmation
        ) { confirmation in
            Button("취소", role: .cancel) {
                rejectionConfirmation = nil
            }
            Button("확인", role: .destructive) {
                rejectionConfirmation = nil
                Task {
                    await viewModel.reject(
                        confirmation.group,
                        reason: confirmation.reason
                    )
                }
            }
        } message: { confirmation in
            Text("\(confirmation.group.displayNameSnapshot) 요청을 보류할까요? 이유: \(confirmation.reason.displayTitle)")
        }
        .alert(
            "처리 시작",
            isPresented: Binding(
                get: { processingTarget != nil },
                set: { isPresented in
                    if !isPresented {
                        processingTarget = nil
                    }
                }
            ),
            presenting: processingTarget
        ) { group in
            Button("취소", role: .cancel) {
                processingTarget = nil
            }
            Button("확인") {
                processingTarget = nil
                Task {
                    await viewModel.startProcessing(group)
                }
            }
        } message: { group in
            Text("\(group.displayNameSnapshot) 요청 처리를 시작할까요?")
        }
        .alert(
            "요청 완료",
            isPresented: Binding(
                get: { viewModel.pendingCompletion != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.cancelPendingCompletion()
                    }
                }
            ),
            presenting: viewModel.pendingCompletion
        ) { pending in
            Button("취소", role: .destructive) {
                viewModel.cancelPendingCompletion()
            }
            Button("확인") {
                viewModel.cancelPendingCompletion()
                Task { await viewModel.confirmCompletion(pending) }
            }
        } message: { pending in
            Text(completionConfirmMessage(for: pending))
        }
        .fullScreenCover(isPresented: $isPresentingCreateBrand, onDismiss: {
            guard let completionTarget, let createdBrandID else {
                self.completionTarget = nil
                self.createdBrandID = nil
                return
            }
            viewModel.prepareCompletion(
                group: completionTarget,
                resolvedBrandID: createdBrandID
            )
            self.completionTarget = nil
            self.createdBrandID = nil
        }) {
            NavigationView {
                createBrandFlowFactory { createdBrandID in
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
            if viewModel.groups.isEmpty {
                emptyState
            } else {
                groupList
            }
        }
    }

    private var groupList: some View {
        List {
            ForEach(viewModel.groups) { group in
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
                        createAndComplete: {
                            completionTarget = group
                            isPresentingCreateBrand = true
                        }
                    )
                )
                .listRowBackground(OutPickTheme.SwiftUIColor.backgroundBase)
                .onAppear {
                    Task {
                        await viewModel.loadNextPageIfNeeded(current: group)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.reload()
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
            Text("상태를 바꾸면 이 목록에서 자동으로 이동해요.")
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
            return "보류된 요청이 없어요"
        case .completed:
            return "완료된 요청이 없어요"
        }
    }

    private func completionConfirmMessage(
        for pending: AdminBrandRequestGroupsViewModel.PendingCompletion
    ) -> String {
        "\(pending.group.displayNameSnapshot) 요청을 생성한 브랜드와 연결하고 완료 처리할까요?"
    }
}

private struct RejectionConfirmation: Identifiable {
    let group: AdminBrandRequestGroup
    let reason: BrandRequestRejectionReason

    var id: String {
        "\(group.id)_\(reason.rawValue)"
    }
}

private struct AdminBrandRequestGroupRowView: View {
    struct Actions {
        let startProcessing: () -> Void
        let reject: () -> Void
        let createAndComplete: () -> Void
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
        } else {
            Menu {
                if group.adminStage != .processing {
                    Button(action: actions.startProcessing) {
                        Label("처리 시작", systemImage: "play.fill")
                    }
                }

                if group.adminStage != .rejected {
                    Button(role: .destructive, action: actions.reject) {
                        Label("보류", systemImage: "xmark")
                    }
                }

                if group.adminStage == .processing {
                    Button(action: actions.createAndComplete) {
                        Label("브랜드 생성 후 완료", systemImage: "checkmark")
                    }
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
