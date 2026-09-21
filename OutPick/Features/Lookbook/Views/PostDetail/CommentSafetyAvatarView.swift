//
//  CommentSafetyAvatarView.swift
//  OutPick
//
//  Created by Codex on 5/11/26.
//

import SwiftUI
import UIKit

struct CommentSafetyAvatarView: View {
    let userID: String
    let avatarPath: String?
    let size: CGFloat
    let avatarImageManager: AvatarImageManaging

    @StateObject private var presentation = AvatarImagePresentationState()
    @Environment(\.avatarRefreshID) private var refreshID
    private var identity: AvatarImageIdentity { AvatarImageIdentity(userID: userID, path: avatarPath) }
    private var displayedImage: UIImage? {
        if presentation.identity == identity, let image = presentation.image { return image }
        return identity.path.flatMap { avatarImageManager.cachedAvatarImmediately(for: $0) }
    }

    var body: some View {
        Group {
            if let image = displayedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("Default_Profile")
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .background(Circle().fill(OutPickTheme.SwiftUIColor.surfaceElevated))
        .onAppear { configure(identity); presentation.resume() }
        .onChange(of: identity) { next in
            // 콜백이 캡처한 이전 View 대신 변경 이벤트의 최신 경로를 적용한다.
            configure(next)
        }
        .onDisappear { presentation.suspend() }
        .onChange(of: refreshID) { _ in presentation.refreshFailure() }
    }

    private func configure(_ next: AvatarImageIdentity) {
        presentation.configure(userID: next.userID, path: next.path, manager: avatarImageManager)
    }

}
