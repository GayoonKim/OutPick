import SwiftUI

struct SeasonImportManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SeasonImportManagementViewModel
    private let showsNavigationChrome: Bool

    init(
        viewModel: SeasonImportManagementViewModel,
        showsNavigationChrome: Bool = true
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.showsNavigationChrome = showsNavigationChrome
    }

    var body: some View {
        Group {
            if showsNavigationChrome {
                NavigationView {
                    content
                        .navigationTitle("시즌 가져오기 현황")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("닫기") {
                                    dismiss()
                                }
                            }
                        }
                }
                .navigationViewStyle(StackNavigationViewStyle())
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if viewModel.isLoading && viewModel.jobs.isEmpty {
                ProgressView("시즌 가져오기 현황을 불러오는 중입니다.")
                    .tint(OutPickTheme.SwiftUIColor.accent)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.jobs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.title)
                    Text("가져오기 기록이 없습니다")
                        .font(.headline)
                }
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(viewModel.jobs) { job in
                            jobRow(job)
                                .padding(14)
                                .background(OutPickTheme.SwiftUIColor.surfaceBase)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                    .padding(showsNavigationChrome ? 16 : 0)
                }
                .refreshable {
                    await viewModel.load()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
        .tint(OutPickTheme.SwiftUIColor.accent)
        .task {
            await viewModel.monitor()
        }
        .appToast(message: viewModel.errorMessage) {
            viewModel.clearError()
        }
    }

    private func jobRow(_ job: SeasonImportJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(jobTitle(job))
                    .font(.headline)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                Spacer()
                Text(statusText(job.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(job.status))
            }

            Text(phaseText(job.phase))
                .font(.subheadline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)

            if job.assetCompletedCount > 0 || job.assetFailedCount > 0 {
                Text(
                    "이미지 \(job.assetCompletedCount + job.assetFailedCount)개 중 \(job.assetCompletedCount)개 완료, \(job.assetFailedCount)개 실패"
                )
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }

            if job.canRetryAssets || viewModel.hasActiveRetry(for: job) {
                HStack {
                    Spacer()
                    Button {
                        Task {
                            await viewModel.retryAssets(for: job)
                        }
                    } label: {
                        if viewModel.retryingJobID == job.id {
                            ProgressView()
                                .tint(OutPickTheme.SwiftUIColor.accent)
                                .frame(width: 44)
                        } else if viewModel.hasActiveRetry(for: job) {
                            Text("재시도 중")
                        } else {
                            Text("재시도")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(
                        viewModel.retryingJobID != nil ||
                        viewModel.hasActiveRetry(for: job)
                    )
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func jobTitle(_ job: SeasonImportJob) -> String {
        switch job.jobType {
        case .importSeasonFromURL:
            return job.displayTitle
        case .retrySeasonAssets:
            return "이미지 재시도"
        }
    }

    private func statusText(_ status: SeasonImportJobStatus) -> String {
        switch status {
        case .queued: return "대기 중"
        case .processing: return "처리 중"
        case .succeeded: return "완료"
        case .partialFailed: return "일부 실패"
        case .failed: return "실패"
        case .cancelled: return "취소"
        }
    }

    private func phaseText(_ phase: SeasonImportJobPhase) -> String {
        switch phase {
        case .dispatching: return "작업 요청을 전달하고 있습니다."
        case .parsing: return "시즌 페이지를 분석하고 있습니다."
        case .materializing: return "시즌과 포스트를 만들고 있습니다."
        case .syncingAssets: return "이미지를 저장하고 있습니다."
        case .completed: return "작업이 종료되었습니다."
        }
    }

    private func statusColor(_ status: SeasonImportJobStatus) -> Color {
        switch status {
        case .succeeded:
            return OutPickTheme.SwiftUIColor.success
        case .partialFailed, .failed:
            return OutPickTheme.SwiftUIColor.warning
        case .cancelled:
            return OutPickTheme.SwiftUIColor.textSecondary
        case .queued, .processing:
            return OutPickTheme.SwiftUIColor.accent
        }
    }
}

private extension View {
    @ViewBuilder
    func outpickHiddenScrollContentBackground() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
