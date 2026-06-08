//
//  PostCommentInputBarView.swift
//  OutPick
//
//  Created by Codex on 5/4/26.
//

import SwiftUI
import UIKit

struct PostCommentInputBarView: View {
    @Binding var text: String

    let placeholder: String
    let isSubmitting: Bool
    let canSubmit: Bool
    let submitAccessibilityLabel: String
    let onSubmit: () async -> Void

    @State private var inputHeight: CGFloat = Constants.minInputHeight

    init(
        text: Binding<String>,
        placeholder: String,
        isSubmitting: Bool,
        canSubmit: Bool,
        submitAccessibilityLabel: String = "댓글 등록",
        onSubmit: @escaping () async -> Void
    ) {
        _text = text
        self.placeholder = placeholder
        self.isSubmitting = isSubmitting
        self.canSubmit = canSubmit
        self.submitAccessibilityLabel = submitAccessibilityLabel
        self.onSubmit = onSubmit
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .topLeading) {
                GrowingCommentTextView(
                    text: $text,
                    measuredHeight: $inputHeight,
                    minHeight: Constants.minInputHeight,
                    maxHeight: Constants.maxInputHeight
                )
                .frame(height: inputHeight)
                .padding(.horizontal, 12)
                .accessibilityIdentifier("lookbook.comment.input")

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(placeholder)
                        .font(.subheadline)
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }
            .background(OutPickTheme.SwiftUIColor.surfaceBase)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(OutPickTheme.SwiftUIColor.borderSubtle, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .animation(.easeInOut(duration: 0.12), value: inputHeight)

            Button {
                Task {
                    await onSubmit()
                }
            } label: {
                Group {
                    if isSubmitting {
                        ProgressView()
                            .tint(OutPickTheme.SwiftUIColor.backgroundBase)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .foregroundStyle(OutPickTheme.SwiftUIColor.backgroundBase)
                .frame(width: 42, height: 42)
                .background(
                    canSubmit
                        ? OutPickTheme.SwiftUIColor.accent
                        : OutPickTheme.SwiftUIColor.surfaceElevated
                )
                .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(canSubmit == false)
            .accessibilityLabel(submitAccessibilityLabel)
            .accessibilityIdentifier("lookbook.comment.submitButton")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
    }
}

private enum Constants {
    static let minInputHeight: CGFloat = 38
    static let maxInputHeight: CGFloat = 112
}

private struct GrowingCommentTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var measuredHeight: CGFloat

    let minHeight: CGFloat
    let maxHeight: CGFloat

    func makeUIView(context: Context) -> LayoutAwareTextView {
        let textView = LayoutAwareTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .subheadline)
        textView.textColor = OutPickTheme.ColorToken.textPrimary
        textView.tintColor = OutPickTheme.ColorToken.accent
        textView.textContainerInset = UIEdgeInsets(
            top: 8,
            left: 0,
            bottom: 8,
            right: 0
        )
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = true
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.onLayout = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView else { return }
            coordinator?.updateHeight(for: textView)
        }
        return textView
    }

    func updateUIView(_ uiView: LayoutAwareTextView, context: Context) {
        context.coordinator.parent = self

        if uiView.text != text {
            uiView.text = text
        }
        uiView.font = .preferredFont(forTextStyle: .subheadline)
        uiView.textColor = OutPickTheme.ColorToken.textPrimary
        uiView.tintColor = OutPickTheme.ColorToken.accent
        context.coordinator.updateHeight(for: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingCommentTextView

        init(parent: GrowingCommentTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            updateHeight(for: textView)
        }

        func updateHeight(for textView: UITextView) {
            let width = textView.bounds.width
            guard width > 0 else { return }

            let fittingSize = CGSize(
                width: width,
                height: .greatestFiniteMagnitude
            )
            let rawHeight = textView.sizeThatFits(fittingSize).height
            let nextHeight = min(max(rawHeight, parent.minHeight), parent.maxHeight)
            let shouldScroll = rawHeight > parent.maxHeight

            if textView.isScrollEnabled != shouldScroll {
                textView.isScrollEnabled = shouldScroll
            }

            guard abs(parent.measuredHeight - nextHeight) > 0.5 else {
                return
            }

            DispatchQueue.main.async {
                self.parent.measuredHeight = nextHeight
            }
        }
    }
}

private final class LayoutAwareTextView: UITextView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
