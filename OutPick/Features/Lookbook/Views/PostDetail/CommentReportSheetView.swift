//
//  CommentReportSheetView.swift
//  OutPick
//
//  Created by Codex on 5/11/26.
//

import SwiftUI

struct CommentReportSheetView: View {
    let author: CommentAuthorDisplay
    let isReporting: Bool
    let onCancel: () -> Void
    let onSubmit: (CommentReportReason, String?) -> Void

    @State private var selectedReason: CommentReportReason = .spam
    @State private var detailText: String = ""

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(OutPickTheme.SwiftUIColor.borderSubtle)
                .frame(width: 38, height: 5)
                .padding(.top, 10)

            VStack(spacing: 12) {
                CommentSafetyAvatarView(avatarPath: author.avatarPath, size: 58)

                VStack(spacing: 4) {
                    Text("\(author.nickname)님의 댓글을 신고할까요?")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("신고는 운영 검토를 위해 접수되며, 상대방에게 신고 사실을 알리지 않습니다.")
                        .font(.footnote)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("신고 사유")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                VStack(spacing: 0) {
                    ForEach(CommentReportReason.allCases, id: \.self) { reason in
                        Button {
                            selectedReason = reason
                        } label: {
                            HStack(spacing: 12) {
                                Text(reason.title)
                                    .font(.subheadline)
                                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)

                                Spacer()

                                Image(systemName: selectedReason == reason ? "checkmark.circle.fill" : "circle")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(
                                        selectedReason == reason
                                            ? OutPickTheme.SwiftUIColor.accent
                                            : OutPickTheme.SwiftUIColor.iconSecondary
                                    )
                            }
                            .frame(height: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if reason != CommentReportReason.allCases.last {
                            Divider()
                                .background(OutPickTheme.SwiftUIColor.borderSubtle)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(OutPickTheme.SwiftUIColor.surfaceBase)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if selectedReason == .other {
                    TextEditor(text: $detailText)
                        .font(.subheadline)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .scrollContentBackgroundHiddenIfAvailable()
                        .frame(minHeight: 86, maxHeight: 110)
                        .padding(10)
                        .background(OutPickTheme.SwiftUIColor.surfaceBase)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if detailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("신고 사유를 입력해주세요.")
                                    .font(.subheadline)
                                    .foregroundStyle(OutPickTheme.SwiftUIColor.textTertiary)
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onChange(of: detailText) { newValue in
                            if newValue.count > 500 {
                                detailText = String(newValue.prefix(500))
                            }
                        }

                    Text("\(detailText.count)/500")
                        .font(.caption)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                Button(role: .destructive) {
                    onSubmit(selectedReason, reportDetail)
                } label: {
                    HStack {
                        if isReporting {
                            ProgressView()
                                .tint(OutPickTheme.SwiftUIColor.backgroundBase)
                        }
                        Text("신고하기")
                            .font(.subheadline.weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(OutPickTheme.SwiftUIColor.destructive)
                    .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isReporting || canSubmitReport == false)
                .accessibilityIdentifier("lookbook.comment.reportSubmitButton")

                Button {
                    onCancel()
                } label: {
                    Text("취소")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .background(OutPickTheme.SwiftUIColor.surfaceBase)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isReporting)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .background(OutPickTheme.SwiftUIColor.backgroundBase.ignoresSafeArea())
    }

    private var reportDetail: String? {
        let normalizedDetail = detailText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedReason == .other, normalizedDetail.isEmpty == false else {
            return nil
        }
        return normalizedDetail
    }

    private var canSubmitReport: Bool {
        guard selectedReason == .other else { return true }
        return reportDetail != nil
    }
}

private extension View {
    @ViewBuilder
    func scrollContentBackgroundHiddenIfAvailable() -> some View {
        if #available(iOS 16.0, *) {
            scrollContentBackground(.hidden)
        } else {
            self
        }
    }
}
