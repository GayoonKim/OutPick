import Foundation
import FirebaseFunctions

struct ChatVideoPlaybackResource: Hashable, Sendable {
    let roomID: String
    let messageID: String
    let attachmentID: String
    let path: String
    let generation: String
    let mediaExpiresAt: Date

    init?(roomID: String, messageID: String, attachmentID: String?, path: String?, generation: String?, mediaExpiresAt: Date?) {
        guard !roomID.isEmpty, !messageID.isEmpty,
              let attachmentID, !attachmentID.isEmpty, let path, !path.isEmpty,
              let generation, !generation.isEmpty, let mediaExpiresAt else { return nil }
        self.roomID = roomID
        self.messageID = messageID
        self.attachmentID = attachmentID
        self.path = path
        self.generation = generation
        self.mediaExpiresAt = mediaExpiresAt
    }

    var original: ChatOriginalResource {
        ChatOriginalResource(path: path, version: generation,
            maximumBytes: Int(AVAssetExportVideoCompressor.maxChatSourceBytes), mediaExpiresAt: mediaExpiresAt)
    }
}

struct ChatVideoPlaybackURL: Sendable {
    let url: URL
    let urlExpiresAt: Date
    let mediaExpiresAt: Date
}

enum ChatVideoPlaybackError: LocalizedError, Equatable {
    case expired, unavailable, permissionDenied, invalidResponse, temporarilyUnavailable
    var errorDescription: String? {
        switch self {
        case .expired: "보관 기간이 만료된 동영상입니다"
        case .unavailable: "동영상을 찾을 수 없습니다."
        case .permissionDenied: "동영상을 열 수 있는 권한이 없습니다."
        case .invalidResponse, .temporarilyUnavailable: "동영상을 불러오지 못했습니다. 다시 시도해 주세요."
        }
    }
}

protocol ChatVideoPlaybackURLRepository {
    func issue(for resource: ChatVideoPlaybackResource) async throws -> ChatVideoPlaybackURL
}

final class CloudFunctionsChatVideoPlaybackURLRepository: ChatVideoPlaybackURLRepository {
    private let transport: any CloudFunctionsTransporting
    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) { self.transport = transport }

    func issue(for resource: ChatVideoPlaybackResource) async throws -> ChatVideoPlaybackURL {
        do {
            let response = try await transport.call("issueChatVideoPlaybackURL", data: [
                "roomID": resource.roomID, "messageID": resource.messageID, "attachmentID": resource.attachmentID
            ])
            let decoder = CloudFunctionResponseDecoder(dictionary: response)
            guard let url = URL(string: try decoder.string("url")), url.scheme == "https", url.host != nil,
                  let urlExpiresAt = decoder.optionalDate("urlExpiresAt"),
                  let mediaExpiresAt = decoder.optionalDate("mediaExpiresAt"),
                  urlExpiresAt <= mediaExpiresAt,
                  abs(mediaExpiresAt.timeIntervalSince(resource.mediaExpiresAt)) < 0.001 else {
                throw ChatVideoPlaybackError.invalidResponse
            }
            return ChatVideoPlaybackURL(url: url, urlExpiresAt: urlExpiresAt, mediaExpiresAt: mediaExpiresAt)
        } catch let error as ChatVideoPlaybackError { throw error }
        catch {
            let error = error as NSError
            let details = error.userInfo[FunctionsErrorDetailsKey] as? [String: Any]
            if details?["errorCode"] as? String == "MEDIA_EXPIRED" { throw ChatVideoPlaybackError.expired }
            if error.domain == FunctionsErrorDomain {
                switch FunctionsErrorCode(rawValue: error.code) {
                case .permissionDenied, .unauthenticated: throw ChatVideoPlaybackError.permissionDenied
                case .notFound: throw ChatVideoPlaybackError.unavailable
                default: break
                }
            }
            // 서명 URL이나 SDK 오류의 요청 URL을 화면/로그로 넘기지 않는다.
            throw ChatVideoPlaybackError.temporarilyUnavailable
        }
    }
}
