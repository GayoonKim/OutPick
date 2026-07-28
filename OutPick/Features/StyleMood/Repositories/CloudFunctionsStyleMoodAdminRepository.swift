import Foundation

struct CloudFunctionsStyleMoodAdminRepository: StyleMoodAdminRepositoryProtocol {
    private let transport: any CloudFunctionsTransporting

    init(transport: any CloudFunctionsTransporting = FirebaseCloudFunctionsTransport()) {
        self.transport = transport
    }

    func createMood(_ draft: StyleMoodMutationDraft) async throws -> String {
        var data: [String: Any] = [
            "displayName": draft.displayName,
            "displayGroup": draft.displayGroup.rawValue,
            "aliases": draft.aliases,
            "isFeaturedInOnboarding": draft.isFeaturedInOnboarding
        ]
        if let moodID = draft.moodID, moodID.isEmpty == false {
            data["moodID"] = moodID
        }
        if let sortOrder = draft.sortOrder {
            data["sortOrder"] = sortOrder
        }
        let response = try await transport.call("createStyleMood", data: data)
        return try CloudFunctionResponseDecoder(dictionary: response).string("moodID")
    }

    func updateMood(
        moodID: String,
        draft: StyleMoodMutationDraft,
        status: StyleMoodStatus
    ) async throws {
        var data: [String: Any] = [
            "moodID": moodID,
            "displayName": draft.displayName,
            "displayGroup": draft.displayGroup.rawValue,
            "aliases": draft.aliases,
            "isFeaturedInOnboarding": draft.isFeaturedInOnboarding,
            "status": status.rawValue
        ]
        if let sortOrder = draft.sortOrder {
            data["sortOrder"] = sortOrder
        }
        _ = try await transport.call("updateStyleMood", data: data)
    }
}
