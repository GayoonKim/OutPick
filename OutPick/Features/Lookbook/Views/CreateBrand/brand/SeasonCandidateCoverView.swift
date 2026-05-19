//
//  SeasonCandidateCoverView.swift
//  OutPick
//
//  Created by Codex on 4/24/26.
//

import SwiftUI
import UIKit

struct SeasonCandidateCoverView: View {
    let coverImageURL: String?
    let sourceArchiveURL: String

    @State private var uiImage: UIImage?
    @State private var didFail: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(red: 0.94, green: 0.93, blue: 0.90))

            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else if didFail || coverImageURL == nil {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView()
                    .scaleEffect(0.75)
                    .tint(.black)
            }
        }
        .frame(width: 74, height: 92)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: coverImageURL) {
            await loadCoverImage()
        }
    }

    private func loadCoverImage() async {
        uiImage = nil
        didFail = false

        guard let coverImageURL, let url = URL(string: coverImageURL) else {
            didFail = true
            return
        }

        var request = URLRequest(url: url)
        request.setValue(
            "OutPick/1.0 (iOS; lookbook candidate preview)",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        if URL(string: sourceArchiveURL) != nil {
            request.setValue(sourceArchiveURL, forHTTPHeaderField: "Referer")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode),
                let image = UIImage(data: data)
            else {
                didFail = true
                return
            }

            uiImage = image
        } catch {
            didFail = true
        }
    }
}
