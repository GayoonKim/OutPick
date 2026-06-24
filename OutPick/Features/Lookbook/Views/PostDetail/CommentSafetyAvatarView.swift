//
//  CommentSafetyAvatarView.swift
//  OutPick
//
//  Created by Codex on 5/11/26.
//

import SwiftUI
import UIKit

struct CommentSafetyAvatarView: View {
    let avatarPath: String?
    let size: CGFloat
    let avatarImageManager: ChatAvatarImageManaging

    @State private var image: UIImage?
    @State private var loadedPath: String?

    var body: some View {
        Group {
            if let image {
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
        .task(id: avatarPath) {
            await loadAvatarIfNeeded()
        }
    }

    private func loadAvatarIfNeeded() async {
        let normalizedPath = avatarPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedPath, normalizedPath.isEmpty == false else {
            image = nil
            loadedPath = nil
            return
        }
        guard loadedPath != normalizedPath else { return }

        loadedPath = normalizedPath
        if let cachedImage = await avatarImageManager.cachedAvatar(for: normalizedPath) {
            image = cachedImage
            return
        }

        image = try? await avatarImageManager.loadAvatar(
            for: normalizedPath,
            maxBytes: 3 * 1024 * 1024
        )
    }
}
