import Testing
@testable import OutPick

struct CloudFunctionsStyleMoodAdminRepositoryTests {
    @Test
    func moodAndSeasonMutationsUseExpectedCallablePayloads() async throws {
        let transport = CloudFunctionsTransportSpy()
        transport.responses = [
            ["moodID": "new_mood"],
            ["moodID": "new_mood"],
            ["brandID": "brand-1", "seasonID": "season-1", "moodIDs": ["new_mood"]]
        ]
        let moodRepository = CloudFunctionsStyleMoodAdminRepository(transport: transport)
        let seasonRepository = CloudFunctionsSeasonMoodAdminRepository(transport: transport)
        let draft = StyleMoodMutationDraft(
            moodID: nil,
            displayName: "뉴 무드",
            displayGroup: .street,
            aliases: ["new mood"],
            sortOrder: 300,
            isFeaturedInOnboarding: false
        )

        let moodID = try await moodRepository.createMood(draft)
        try await moodRepository.updateMood(
            moodID: moodID,
            draft: draft,
            status: .inactive
        )
        try await seasonRepository.updateSeasonMoods(
            brandID: BrandID(value: "brand-1"),
            seasonID: SeasonID(value: "season-1"),
            moodIDs: [moodID]
        )

        #expect(transport.calls.map(\.name) == [
            "createStyleMood",
            "updateStyleMood",
            "updateSeasonMoods"
        ])
        #expect(transport.calls[0].data["displayGroup"] as? String == "스트릿·트렌드")
        #expect(transport.calls[1].data["status"] as? String == "inactive")
        #expect(transport.calls[2].data["moodIDs"] as? [String] == ["new_mood"])
    }
}
