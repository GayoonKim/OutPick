//
//  MyBrandRequestsView.swift
//  OutPick
//
//  Created by Codex on 7/6/26.
//

import SwiftUI

struct MyBrandRequestsView: View {
    @StateObject private var viewModel: MyBrandRequestsViewModel
    private let coordinator: LookbookCoordinator

    init(
        viewModel: MyBrandRequestsViewModel,
        coordinator: LookbookCoordinator
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.coordinator = coordinator
    }

    var body: some View {
        VStack(spacing: 0) {
            scopePicker
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            content
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .lookbookNavigationBar(
            title: "브랜드 요청 상황",
            showsBackButton: true,
            onBack: { coordinator.pop() }
        ) {
            LookbookNavigationIconButton(
                systemImage: "plus",
                accessibilityLabel: "새 브랜드 요청"
            ) {
                coordinator.pushBrandRequestFromRequestSituation(initialBrandName: "")
            }
        }
        .onAppear {
            Task {
                await viewModel.reload()
            }
        }
        .task {
            await viewModel.loadInitial()
        }
    }

    private var scopePicker: some View {
        Picker("요청 범위", selection: Binding(
            get: { viewModel.scope },
            set: { scope in
                Task { await viewModel.selectScope(scope) }
            }
        )) {
            Text("진행 중").tag(BrandRequestListScope.active)
            Text("이전 요청").tag(BrandRequestListScope.history)
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
                Text("요청을 불러오지 못했어요")
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                Button("다시 시도") {
                    Task { await viewModel.reload() }
                }
                .tint(OutPickTheme.SwiftUIColor.accent)
            }
            .padding(.horizontal, 24)
            Spacer()

        case .ready:
            if viewModel.requests.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text(emptyTitle)
                        .font(.headline)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    Text(emptySubtitle)
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 28)
                Spacer()
            } else {
                List {
                    ForEach(viewModel.requests) { request in
                        BrandRequestRowView(request: request)
                            .listRowBackground(OutPickTheme.SwiftUIColor.backgroundBase)
                            .onAppear {
                                Task {
                                    await viewModel.loadNextPageIfNeeded(current: request)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await viewModel.reload()
                }
            }
        }
    }

    private var emptyTitle: String {
        viewModel.scope == .active ? "진행 중인 요청이 없어요" : "이전 요청이 없어요"
    }

    private var emptySubtitle: String {
        viewModel.scope == .active
            ? "찾는 브랜드가 없을 때 요청하면 여기에서 상태를 볼 수 있어요."
            : "완료되거나 보류된 요청이 여기에 모여요."
    }
}

private struct BrandRequestRowView: View {
    let request: BrandRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(request.brandName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(request.status.displayTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(statusColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            if let updatedAt = request.updatedAt {
                Text(Self.dateFormatter.string(from: updatedAt))
                    .font(.caption)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textTertiary)
            }
        }
        .padding(.vertical, 10)
    }

    private var statusColor: Color {
        switch request.status {
        case .submitted:
            return OutPickTheme.SwiftUIColor.accent
        case .reviewing:
            return OutPickTheme.SwiftUIColor.warning
        case .added:
            return OutPickTheme.SwiftUIColor.success
        case .rejected:
            return OutPickTheme.SwiftUIColor.textSecondary
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
