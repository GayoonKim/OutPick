import Foundation
import UIKit

struct LookbookRemotePreviewImageRequest: Hashable {
    let remoteURL: URL
    let sourcePageURL: URL?
}

protocol LookbookRemotePreviewImageLoading: AnyObject {
    func loadImage(
        request: LookbookRemotePreviewImageRequest,
        maxBytes: Int
    ) async throws -> UIImage

    func prefetch(
        requests: [LookbookRemotePreviewImageRequest],
        maxBytes: Int,
        concurrency: Int
    ) async
}
