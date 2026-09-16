import Foundation
import CryptoKit

/// 카드 표시와 프리패치가 같은 Storage 후보 및 외부 URL 대체 후보를 사용한다.
struct LookbookAssetImageRequest: Hashable {
    let storagePaths: [String]
    let remote: LookbookHTTPImageRequest?
    let maxBytes: Int

    init(primaryPath: String?, secondaryPath: String?, remoteURL: URL?, sourcePageURL: URL?, maxBytes: Int) {
        var paths: [String] = []
        for candidate in [primaryPath, secondaryPath] {
            guard let candidate else { continue }
            let path = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty && !paths.contains(path) { paths.append(path) }
        }
        storagePaths = paths
        remote = remoteURL.map {
            LookbookHTTPImageRequest(remoteURL: $0, sourcePageURL: sourcePageURL, maxBytes: maxBytes)
        }
        self.maxBytes = maxBytes
    }

    var identity: String {
        let paths = storagePaths.map { "\($0.utf8.count):\($0)" }.joined()
        let raw = "\(storagePaths.count):\(paths)\(remote?.key ?? ""):\(maxBytes)"
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
