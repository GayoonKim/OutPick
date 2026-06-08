//
//  LookbookNavigationBar.swift
//  OutPick
//
//  Created by Codex on 6/8/26.
//

import SwiftUI

struct LookbookNavigationBar<Trailing: View>: View {
    let title: String
    var showsBackButton = false
    var onBack: (() -> Void)?
    let trailing: Trailing

    init(
        title: String,
        showsBackButton: Bool = false,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.showsBackButton = showsBackButton
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                if showsBackButton {
                    LookbookNavigationIconButton(
                        systemImage: "chevron.left",
                        accessibilityLabel: "뒤로 가기"
                    ) {
                        onBack?()
                    }
                }

                if title.isEmpty == false {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .layoutPriority(1)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
        .frame(height: 44)
        .padding(.horizontal, 20)
        .padding(.bottom, 5)
        .background(OutPickTheme.SwiftUIColor.backgroundBase)
    }
}

extension LookbookNavigationBar where Trailing == EmptyView {
    init(
        title: String,
        showsBackButton: Bool = false,
        onBack: (() -> Void)? = nil
    ) {
        self.title = title
        self.showsBackButton = showsBackButton
        self.onBack = onBack
        self.trailing = EmptyView()
    }
}

struct LookbookNavigationIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    var foregroundColor = OutPickTheme.SwiftUIColor.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            LookbookNavigationIconLabel(
                systemImage: systemImage,
                foregroundColor: foregroundColor
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct LookbookNavigationIconLabel: View {
    let systemImage: String
    var foregroundColor = OutPickTheme.SwiftUIColor.accent

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .frame(width: 40, height: 40)
            .background(OutPickTheme.SwiftUIColor.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct LookbookNavigationTextButton: View {
    let title: String
    let systemImage: String?
    let accessibilityLabel: String
    let action: () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 13, height: 13)
                }

                Text(title)
                    .font(.system(size: 12, weight: .heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(OutPickTheme.SwiftUIColor.accent)
            .frame(height: 40)
            .padding(.horizontal, 12)
            .background(OutPickTheme.SwiftUIColor.surfaceBase)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    func lookbookNavigationBar<Trailing: View>(
        title: String,
        showsBackButton: Bool = false,
        onBack: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) -> some View {
        navigationBarHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                LookbookNavigationBar(
                    title: title,
                    showsBackButton: showsBackButton,
                    onBack: onBack,
                    trailing: trailing
                )
            }
    }

    func lookbookNavigationBar(
        title: String,
        showsBackButton: Bool = false,
        onBack: (() -> Void)? = nil
    ) -> some View {
        lookbookNavigationBar(
            title: title,
            showsBackButton: showsBackButton,
            onBack: onBack
        ) {
            EmptyView()
        }
    }
}
