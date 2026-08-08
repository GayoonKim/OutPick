import Foundation

final class CloudFunctionsCurrentUserModerationRepository:
    CurrentUserModerationRepositoryProtocol {
    private let transport: CloudFunctionsTransporting

    init(transport: CloudFunctionsTransporting) {
        self.transport = transport
    }

    func fetchAndBindCurrentState() async throws -> CurrentUserModerationState {
        let response = try await transport.call("getMyModerationState", data: [:])
        let decoder = CloudFunctionResponseDecoder(dictionary: response)
        guard let status = AccountModerationStatus(
            rawValue: try decoder.string("moderationStatus")
        ) else {
            throw CloudFunctionsClientError.invalidResponse
        }
        let capabilities = Set(
            decoder.stringArray("allowedCapabilities")
                .compactMap(ModerationCapability.init(rawValue:))
        )
        return CurrentUserModerationState(
            status: status,
            restrictedUntil: decoder.optionalDate("restrictedUntil"),
            allowedCapabilities: capabilities,
            noticeReasonCode: decoder.optionalString("noticeReasonCode"),
            supportURL: decoder.optionalString("supportURL").flatMap(URL.init(string:))
        )
    }
}
