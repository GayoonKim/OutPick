//
//  SeasonDetailHeaderCardView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI

struct SeasonDetailHeaderCardView: View {
    let season: Season

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(season.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            HStack(spacing: 10) {
                Label("\(season.postCount) looks", systemImage: "square.grid.2x2")
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)

            if let description = seasonDescription {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.92))
        )
    }

    private var seasonDescription: String? {
        let trimmed = season.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
