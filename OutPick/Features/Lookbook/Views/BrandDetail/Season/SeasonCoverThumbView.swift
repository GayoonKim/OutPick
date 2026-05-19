//
//  SeasonCoverThumbView.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/26.
//

import SwiftUI

struct SeasonCoverThumbView: View {
    let thumbPath: String?
    let fallbackPath: String?
    let remoteURL: String?
    let sourcePageURL: String?
    let brandImageCache: any BrandImageCacheProtocol
    let maxBytes: Int

    var body: some View {
        LookbookAssetImageView(
            primaryPath: thumbPath,
            secondaryPath: fallbackPath,
            remoteURL: remoteURL.flatMap(URL.init(string:)),
            sourcePageURL: sourcePageURL.flatMap(URL.init(string:)),
            brandImageCache: brandImageCache,
            maxBytes: maxBytes
        )
    }
}
