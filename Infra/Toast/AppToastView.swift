//
//  AppToastView.swift
//  OutPick
//
//  Created by Codex on 5/12/26.
//

import SwiftUI

struct AppToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)

            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("app.toast")
    }
}

private struct AppToastModifier: ViewModifier {
    let message: String?
    let bottomPadding: CGFloat
    let duration: TimeInterval
    let onDismiss: () -> Void

    @State private var visibleMessage: String?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let visibleMessage {
                    AppToastView(message: visibleMessage)
                        .padding(.horizontal, 16)
                        .padding(.bottom, bottomPadding)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.86), value: visibleMessage)
            .onAppear {
                present(message)
            }
            .onChange(of: message) { nextMessage in
                present(nextMessage)
            }
            .onDisappear {
                dismissTask?.cancel()
            }
    }

    private func present(_ nextMessage: String?) {
        dismissTask?.cancel()

        guard let nextMessage,
              nextMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            visibleMessage = nil
            return
        }

        visibleMessage = nextMessage
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard Task.isCancelled == false else { return }
            visibleMessage = nil
            onDismiss()
        }
    }
}

extension View {
    func appToast(
        message: String?,
        bottomPadding: CGFloat = 18,
        duration: TimeInterval = 2.4,
        onDismiss: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            AppToastModifier(
                message: message,
                bottomPadding: bottomPadding,
                duration: duration,
                onDismiss: onDismiss
            )
        )
    }
}
