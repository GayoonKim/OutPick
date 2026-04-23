//
//  BrandDetailSeasonsGridView.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/26.
//

import SwiftUI

struct BrandDetailSeasonsGridView: View {
    let seasons: [Season]
    let latestSeasonImportJob: SeasonImportJob?
    let isLoading: Bool
    let errorMessage: String?
    let importJobErrorMessage: String?
    let canRequestSeasonImport: Bool
    let onTapSeasonImportCTA: (() -> Void)?
    let brandImageCache: any BrandImageCacheProtocol
    let maxBytes: Int

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("시즌")
                    .font(.headline)

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.9)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if let latestSeasonImportJob {
                SeasonImportJobStatusCardView(job: latestSeasonImportJob)
                    .padding(.horizontal, 16)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            if let importJobErrorMessage {
                Text(importJobErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            if seasons.isEmpty, !isLoading, errorMessage == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text(emptyStateMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if canRequestSeasonImport, let onTapSeasonImportCTA {
                        Button(action: onTapSeasonImportCTA) {
                            Text(emptyStateButtonTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.black)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(seasons, id: \.id) { season in
                        NavigationLink(
                            destination: SeasonDetailView(
                                brandID: season.brandID,
                                seasonID: season.id
                            )
                        ) {
                            BrandDetailSeasonGridItemView(
                                season: season,
                                brandImageCache: brandImageCache,
                                maxBytes: maxBytes
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private var emptyStateMessage: String {
        guard let latestSeasonImportJob else {
            return "등록된 시즌이 없습니다."
        }

        switch latestSeasonImportJob.status {
        case .queued:
            return "시즌 URL import 요청이 생성되었습니다. 현재 단계에서는 요청 문서만 생성되며, 다음 단계에서 수집 워커를 연결하면 실제 진행 상태로 이어집니다."
        case .running:
            return "시즌 URL import를 진행 중입니다. 시즌 페이지와 이미지를 수집하고 있습니다."
        case .success:
            return "가장 최근 시즌 import 요청이 완료 상태입니다. 시즌이 아직 보이지 않으면 잠시 후 다시 확인해주세요."
        case .failed:
            return latestSeasonImportJob.errorMessage ?? "가장 최근 시즌 import 요청이 실패했습니다. 다른 시즌 URL로 다시 시도해보세요."
        }
    }

    private var emptyStateButtonTitle: String {
        if let latestSeasonImportJob, latestSeasonImportJob.status == .failed {
            return "다른 시즌 URL로 다시 등록"
        }
        return "시즌 URL로 등록"
    }
}

private struct SeasonImportJobStatusCardView: View {
    let job: SeasonImportJob

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                if showsProgress {
                    ProgressView()
                        .scaleEffect(0.9)
                } else {
                    Image(systemName: statusIconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(statusTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(statusDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Text(job.sourceURL)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var showsProgress: Bool {
        job.status == .running
    }

    private var statusIconName: String {
        switch job.status {
        case .queued:
            return "tray.and.arrow.down"
        case .running:
            return "hourglass"
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var statusTint: Color {
        switch job.status {
        case .queued:
            return .blue
        case .running:
            return .blue
        case .success:
            return .green
        case .failed:
            return .orange
        }
    }

    private var statusTitle: String {
        switch job.status {
        case .queued:
            return "시즌 URL import 요청이 큐에 등록되었습니다"
        case .running:
            return "시즌 URL import를 진행 중입니다"
        case .success:
            return "시즌 URL import가 완료되었습니다"
        case .failed:
            return "시즌 URL import가 실패했습니다"
        }
    }

    private var statusDescription: String {
        switch job.status {
        case .queued:
            return "현재 단계에서는 요청 생성까지만 연결되어 있습니다. 이후 수집 워커가 붙으면 여기서 실제 진행 상태를 이어서 보여줄 수 있습니다."
        case .running:
            return "시즌 페이지와 이미지를 수집하는 중입니다."
        case .success:
            return "가져온 시즌이 곧 목록에 반영될 수 있습니다."
        case .failed:
            return job.errorMessage ?? "다시 시도하거나 다른 시즌 URL을 입력해주세요."
        }
    }
}
