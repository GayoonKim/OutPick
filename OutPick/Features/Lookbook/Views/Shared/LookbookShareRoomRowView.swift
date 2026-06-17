//
//  LookbookShareRoomRowView.swift
//  OutPick
//
//  Created by Codex on 6/17/26.
//

import SwiftUI

struct LookbookShareRoomRowView: View {
    let room: ChatRoom
    let isSelected: Bool
    let roomImageManager: any RoomImageManaging
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var representedPath: String?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(OutPickTheme.SwiftUIColor.backgroundRaised)

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
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text(room.roomName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(OutPickTheme.SwiftUIColor.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(
                        isSelected
                            ? OutPickTheme.SwiftUIColor.accent
                            : OutPickTheme.SwiftUIColor.iconSecondary
                    )
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(OutPickTheme.SwiftUIColor.surfaceBase)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        isSelected
                            ? OutPickTheme.SwiftUIColor.accent
                            : OutPickTheme.SwiftUIColor.borderSubtle,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            }
        }
        .buttonStyle(.plain)
        .task(id: room.coverImagePath ?? "") {
            await loadRoomImage()
        }
    }

    private func loadRoomImage() async {
        guard let path = room.coverImagePath, path.isEmpty == false else {
            image = nil
            representedPath = nil
            return
        }

        representedPath = path
        if let cached = await roomImageManager.cachedImage(for: path) {
            guard representedPath == path else { return }
            image = cached
            return
        }

        do {
            let loaded = try await roomImageManager.loadImage(
                for: path,
                maxBytes: 3 * 1024 * 1024
            )
            guard representedPath == path else { return }
            image = loaded
        } catch {
            guard representedPath == path else { return }
            image = nil
        }
    }
}
