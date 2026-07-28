import Foundation
import Testing
@testable import OutPick

struct CloudFunctionsProfileMutationRepositoryTests {
    @Test
    func checkNicknameAvailabilityReturnsServerResult() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [["isAvailable": false]]
        let repository = CloudFunctionsProfileMutationRepository(transport: transport)

        let isAvailable = try await repository.checkNicknameAvailability(
            nickname: "아웃피커"
        )

        #expect(isAvailable == false)
        #expect(transport.calls.count == 1)
        #expect(transport.calls[0].name == "checkNicknameAvailability")
        #expect(transport.calls[0].data["nickname"] as? String == "아웃피커")
    }

    @Test
    func completeOnboardingSendsNicknameAndMoodIDs() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "userID": "user-1",
            "onboardingVersion": 1
        ]]
        let repository = CloudFunctionsProfileMutationRepository(transport: transport)

        let result = try await repository.completeOnboarding(
            nickname: "아웃피커",
            selectedMoodIDs: ["minimal", "street"]
        )

        #expect(result.userID == "user-1")
        #expect(result.onboardingVersion == 1)
        #expect(transport.calls.count == 1)
        #expect(transport.calls[0].name == "completeOnboarding")
        #expect(transport.calls[0].data["nickname"] as? String == "아웃피커")
        #expect(
            transport.calls[0].data["selectedMoodIDs"] as? [String]
                == ["minimal", "street"]
        )
    }

    @Test
    func updatePublicProfileOmitsUnchangedFields() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "userID": "user-1",
            "nickname": "아웃피커",
            "avatarThumbPath": "thumb.jpg",
            "avatarOriginalPath": "original.jpg"
        ]]
        let repository = CloudFunctionsProfileMutationRepository(transport: transport)

        _ = try await repository.updatePublicProfile(
            nickname: nil,
            avatarMutation: .set(
                thumbPath: "thumb.jpg",
                originalPath: "original.jpg"
            )
        )

        #expect(transport.calls[0].name == "updatePublicProfile")
        #expect(transport.calls[0].data["nickname"] == nil)
        #expect(transport.calls[0].data["avatarThumbPath"] as? String == "thumb.jpg")
        #expect(transport.calls[0].data["avatarOriginalPath"] as? String == "original.jpg")
    }

    @Test
    func updatePublicProfileEncodesAvatarRemovalAsNull() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [[
            "userID": "user-1",
            "nickname": "아웃피커",
            "avatarThumbPath": NSNull(),
            "avatarOriginalPath": NSNull()
        ]]
        let repository = CloudFunctionsProfileMutationRepository(transport: transport)

        _ = try await repository.updatePublicProfile(
            nickname: nil,
            avatarMutation: .remove
        )

        #expect(transport.calls[0].data["avatarThumbPath"] is NSNull)
        #expect(transport.calls[0].data["avatarOriginalPath"] is NSNull)
    }
}
