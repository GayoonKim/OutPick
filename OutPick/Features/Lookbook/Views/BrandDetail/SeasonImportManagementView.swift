import SwiftUI

struct SeasonImportManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: SeasonImportManagementViewModel

    init(viewModel: SeasonImportManagementViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoading && viewModel.jobs.isEmpty {
                    ProgressView("가져오기 현황을 불러오는 중입니다.")
                } else if viewModel.jobs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "tray")
                            .font(.title)
                        Text("가져오기 기록이 없습니다")
                            .font(.headline)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    List(viewModel.jobs) { job in
                        jobRow(job)
                    }
                    .refreshable {
                        await viewModel.load()
                    }
                }
            }
            .navigationTitle("가져오기 현황")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.monitor()
            }
            .appToast(message: viewModel.errorMessage) {
                viewModel.clearError()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func jobRow(_ job: SeasonImportJob) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(jobTitle(job))
                    .font(.headline)
                Spacer()
                Text(statusText(job.status))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor(job.status))
            }

            Text(phaseText(job.phase))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if job.assetCompletedCount > 0 || job.assetFailedCount > 0 {
                Text(
                    "이미지 성공 \(job.assetCompletedCount) · 실패 \(job.assetFailedCount)"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            if let errorMessage = job.errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if job.canRetryAssets {
                Button {
                    Task {
                        await viewModel.retryAssets(for: job)
                    }
                } label: {
                    if viewModel.retryingJobID == job.id {
                        ProgressView()
                    } else if viewModel.hasActiveRetry(for: job) {
                        Text("이미지 재시도 진행 중")
                    } else {
                        Text("실패 이미지 다시 가져오기")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(
                    viewModel.retryingJobID != nil ||
                    viewModel.hasActiveRetry(for: job)
                )
            }
        }
        .padding(.vertical, 6)
    }

    private func jobTitle(_ job: SeasonImportJob) -> String {
        switch job.jobType {
        case .importSeasonFromURL:
            return job.targetSeasonID?.value ?? "시즌 가져오기"
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
            return .green
        case .partialFailed, .failed:
            return .orange
        case .cancelled:
            return .secondary
        case .queued, .processing:
            return .blue
        }
    }
}
