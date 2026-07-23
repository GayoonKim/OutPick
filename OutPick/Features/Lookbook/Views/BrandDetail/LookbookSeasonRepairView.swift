import SwiftUI

struct LookbookSeasonRepairView: View {
    private struct PreviewEntry: Identifiable {
        let id: String
        let url: URL
        let detail: String
    }

    @StateObject private var viewModel: LookbookSeasonRepairViewModel
    @State private var scheduledPrefetchIDs = Set<String>()
    private let imageLoader: any LookbookRemotePreviewImageLoading
    private let onBack: () -> Void
    private let previewMaxBytes = 16 * 1024 * 1024
    private let prefetchWindowSize = 8
    private let gridColumns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(
        viewModel: LookbookSeasonRepairViewModel,
        imageLoader: any LookbookRemotePreviewImageLoading,
        onBack: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.imageLoader = imageLoader
        self.onBack = onBack
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.preview == nil {
                VStack(spacing: 14) {
                    Text("현재 시즌과 원본 페이지를 비교하고 있습니다.")
                        .font(.subheadline)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                    ProgressView()
                        .tint(OutPickTheme.SwiftUIColor.accent)
                        .controlSize(.large)
                }
            } else if let preview = viewModel.preview {
                previewContent(preview)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.title)
                    Text("변경 미리보기를 표시할 수 없습니다")
                        .font(.headline)
                    Button("다시 시도") {
                        Task { await viewModel.start() }
                    }
                    .buttonStyle(.bordered)
                }
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .lookbookNavigationBar(
            title: "기존 시즌 보수",
            showsBackButton: true,
            onBack: onBack
        )
        .task { await viewModel.start() }
        .appToast(message: viewModel.errorMessage) {
            viewModel.clearError()
        }
    }

    private func previewContent(
        _ preview: LookbookSeasonRepairPreview
    ) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary(preview)
                section(
                    title: "추가 \(preview.add.count)개",
                    status: "추가",
                    tone: OutPickTheme.SwiftUIColor.accent,
                    entries: preview.add.map {
                        PreviewEntry(
                            id: $0.id,
                            url: $0.sourceURL,
                            detail: "#\($0.proposedIndex + 1)"
                        )
                    }
                )
                section(
                    title: "순서 변경 \(preview.reorder.count)개",
                    status: "순서 변경",
                    tone: OutPickTheme.SwiftUIColor.warning,
                    entries: preview.reorder.map {
                        PreviewEntry(
                            id: $0.id,
                            url: $0.sourceURL,
                            detail:
                                "#\($0.previousIndex + 1) → " +
                                "#\(($0.proposedIndex ?? 0) + 1)"
                        )
                    }
                )
                section(
                    title: "유지 \(preview.keep.count)개",
                    status: "유지",
                    tone: OutPickTheme.SwiftUIColor.success,
                    entries: preview.keep.map {
                        PreviewEntry(
                            id: $0.id,
                            url: $0.sourceURL,
                            detail: "#\($0.previousIndex + 1)"
                        )
                    }
                )
                section(
                    title: "삭제 후보 \(preview.removeCandidates.count)개",
                    status: "삭제 후보",
                    tone: OutPickTheme.SwiftUIColor.destructive,
                    entries: preview.removeCandidates.map {
                        PreviewEntry(
                            id: $0.id,
                            url: $0.sourceURL,
                            detail:
                                "보존 " +
                                "#\(($0.proposedIndex ?? $0.previousIndex) + 1)"
                        )
                    }
                )

                Text("삭제 후보는 이번 적용에서 삭제하지 않고 기존 시즌에 그대로 보존합니다.")
                    .font(.footnote)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.warning)

                Button {
                    Task { await viewModel.apply() }
                } label: {
                    if viewModel.isApplying {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("변경 사항 적용")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isApplying)
            }
            .padding(20)
        }
        .onAppear {
            schedulePrefetch(
                entries: allEntries(preview),
                startingAt: 0
            )
        }
    }

    private func summary(
        _ preview: LookbookSeasonRepairPreview
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("적용 후 포스트 \(preview.resultingPostCount)개")
                .font(.headline)
            Text(
                "추가 \(preview.add.count) · 순서 변경 \(preview.reorder.count) · " +
                "유지 \(preview.keep.count) · 삭제 후보 \(preview.removeCandidates.count)"
            )
            .font(.subheadline)
            .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
    }

    @ViewBuilder
    private func section(
        title: String,
        status: String,
        tone: Color,
        entries: [PreviewEntry]
    ) -> some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                LazyVGrid(columns: gridColumns, spacing: 10) {
                    ForEach(
                        Array(entries.enumerated()),
                        id: \.element.id
                    ) { index, entry in
                        ZStack(alignment: .topLeading) {
                            LookbookRemotePreviewImageView(
                                request: previewRequest(url: entry.url),
                                imageLoader: imageLoader,
                                maxBytes: previewMaxBytes
                            )
                            .frame(height: 220)

                            Text(status)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(tone.opacity(0.9), in: Capsule())
                                .padding(8)

                            VStack {
                                Spacer()
                                HStack {
                                    Text(entry.detail)
                                        .font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .background(.black.opacity(0.62))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(tone.opacity(0.65), lineWidth: 1)
                        }
                        .onAppear {
                            schedulePrefetch(
                                entries: entries,
                                startingAt: index + 1
                            )
                        }
                    }
                }
            }
        }
    }

    private func allEntries(
        _ preview: LookbookSeasonRepairPreview
    ) -> [PreviewEntry] {
        let add = preview.add.map {
            PreviewEntry(
                id: $0.id,
                url: $0.sourceURL,
                detail: "#\($0.proposedIndex + 1)"
            )
        }
        let reorder = preview.reorder.map {
            PreviewEntry(
                id: $0.id,
                url: $0.sourceURL,
                detail:
                    "#\($0.previousIndex + 1) → " +
                    "#\(($0.proposedIndex ?? 0) + 1)"
            )
        }
        let keep = preview.keep.map {
            PreviewEntry(
                id: $0.id,
                url: $0.sourceURL,
                detail: "#\($0.previousIndex + 1)"
            )
        }
        let removeCandidates = preview.removeCandidates.map {
            PreviewEntry(
                id: $0.id,
                url: $0.sourceURL,
                detail:
                    "보존 " +
                    "#\(($0.proposedIndex ?? $0.previousIndex) + 1)"
            )
        }
        return add + reorder + keep + removeCandidates
    }

    private func schedulePrefetch(
        entries: [PreviewEntry],
        startingAt index: Int
    ) {
        guard index < entries.count else { return }
        let upperBound = min(index + prefetchWindowSize, entries.count)
        let targets = entries[index..<upperBound].filter {
            scheduledPrefetchIDs.contains($0.id) == false
        }
        guard !targets.isEmpty else { return }
        scheduledPrefetchIDs.formUnion(targets.map(\.id))
        let requests = targets.map {
            previewRequest(url: $0.url)
        }
        Task {
            await imageLoader.prefetch(
                requests: requests,
                maxBytes: previewMaxBytes,
                concurrency: 4
            )
        }
    }

    private func previewRequest(
        url: URL
    ) -> LookbookRemotePreviewImageRequest {
        LookbookRemotePreviewImageRequest(
            remoteURL: url,
            sourcePageURL: nil
        )
    }
}
