//
//  LookbookShareSheetView.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import SwiftUI

struct LookbookShareSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: LookbookChatShareViewModel

    private let brandImageCache: any BrandImageCacheProtocol
    private let roomImageManager: any RoomImageManaging
    private let onCompleted: (LookbookChatShareViewModel.Completion) -> Void

    init(
        viewModel: LookbookChatShareViewModel,
        brandImageCache: any BrandImageCacheProtocol,
        roomImageManager: any RoomImageManaging,
        onCompleted: @escaping (LookbookChatShareViewModel.Completion) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.brandImageCache = brandImageCache
        self.roomImageManager = roomImageManager
        self.onCompleted = onCompleted
    }

    var body: some View {
        VStack(spacing: 0) {
            content
            footer
        }
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
        .task {
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle, .loading:
            loadingSection
        case .ready:
            roomList
        case .empty:
            statusSection(
                title: "아직 참여 중인 채팅방이 없어요.",
                message: "관심 가는 방에 참여한 뒤 공유해보세요.",
                showsRetry: false
            )
        case .failed(let message):
            statusSection(
                title: "채팅방을 불러오지 못했어요",
                message: message,
                showsRetry: true
            )
        }
    }

    private var roomList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let sharedContent = viewModel.sharedContent {
                    LookbookSharePreviewView(
                        sharedContent: sharedContent,
                        brandImageCache: brandImageCache
                    )
                }

                VStack(spacing: 10) {
                    ForEach(viewModel.rooms, id: \.self) { room in
                        LookbookShareRoomRowView(
                            room: room,
                            isSelected: viewModel.selectedRoomID == room.ID,
                            roomImageManager: roomImageManager
                        ) {
                            viewModel.selectedRoomID = room.ID
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let message = viewModel.sendErrorMessage {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task {
                    await viewModel.send()
                    if let completion = viewModel.completion {
                        onCompleted(completion)
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSending {
                        ProgressView()
                            .controlSize(.small)
                            .tint(OutPickTheme.SwiftUIColor.backgroundBase)
                    } else {
                        Image(systemName: "paperplane.fill")
                    }

                    Text(viewModel.isSending ? "공유 중" : "공유")
                        .font(.headline.weight(.bold))
                }
                .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            viewModel.canSend
                                ? OutPickTheme.SwiftUIColor.accent
                                : OutPickTheme.SwiftUIColor.iconSecondary.opacity(0.35)
                        )
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.canSend == false)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(OutPickTheme.SwiftUIColor.surfaceBase)
    }

    private var loadingSection: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(OutPickTheme.SwiftUIColor.accent)
            Text("공유할 채팅방을 불러오는 중입니다.")
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusSection(
        title: String,
        message: String,
        showsRetry: Bool
    ) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.footnote)
                .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                .multilineTextAlignment(.center)

            if showsRetry {
                Button {
                    Task {
                        await viewModel.retryLoad()
                    }
                } label: {
                    Label("다시 시도", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
