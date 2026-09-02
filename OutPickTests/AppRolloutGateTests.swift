import Foundation
import Testing
@testable import OutPick

@MainActor
struct AppRolloutGateTests {
    @Test func semanticVersionComparesNumericComponents() {
        #expect(AppSemanticVersion("1.10.0")! > AppSemanticVersion("1.9.9")!)
        #expect(AppSemanticVersion("1.0")! == AppSemanticVersion("1.0.0")!)
        #expect(AppSemanticVersion("1.0-beta") == nil)
    }

    @Test func compatibleVersionUsesRemoteFeatureFlag() async {
        let useCase = LoadAppRolloutDecisionUseCase(
            repository: FakeAppRolloutRepository(
                configuration: configuration(minimum: "1.2.0", enabled: true)
            ),
            currentVersion: { "1.2.0" }
        )

        #expect(await useCase.execute() == .available(
            isChatRoomModeratorDelegationEnabled: true
        ))
    }

    @Test func oldVersionRequiresUpdateWithValidatedAppStoreURL() async {
        let useCase = LoadAppRolloutDecisionUseCase(
            repository: FakeAppRolloutRepository(
                configuration: configuration(
                    minimum: "2.0.0",
                    enabled: true,
                    url: "https://apps.apple.com/kr/app/outpick/id123"
                )
            ),
            currentVersion: { "1.9.9" }
        )

        #expect(await useCase.execute() == .updateRequired(
            appStoreURL: URL(string: "https://apps.apple.com/kr/app/outpick/id123")
        ))
    }

    @Test func invalidRemoteVersionFailsOpenForAppButDisablesNewFeature() async {
        let useCase = LoadAppRolloutDecisionUseCase(
            repository: FakeAppRolloutRepository(
                configuration: configuration(minimum: "invalid", enabled: true)
            ),
            currentVersion: { "1.0.0" }
        )

        #expect(await useCase.execute() == .available(
            isChatRoomModeratorDelegationEnabled: false
        ))
    }

    @Test func nonAppleUpdateURLIsRejected() async {
        let useCase = LoadAppRolloutDecisionUseCase(
            repository: FakeAppRolloutRepository(
                configuration: configuration(
                    minimum: "2.0.0",
                    enabled: false,
                    url: "https://example.com/update"
                )
            ),
            currentVersion: { "1.0.0" }
        )

        #expect(await useCase.execute() == .updateRequired(appStoreURL: nil))
    }

    private func configuration(
        minimum: String,
        enabled: Bool,
        url: String? = nil
    ) -> AppRolloutConfiguration {
        AppRolloutConfiguration(
            minimumSupportedIOSVersion: minimum,
            isChatRoomModeratorDelegationEnabled: enabled,
            appStoreURL: url
        )
    }
}

@MainActor
private final class FakeAppRolloutRepository: AppRolloutConfigurationRepositoryProtocol {
    private let configuration: AppRolloutConfiguration

    init(configuration: AppRolloutConfiguration) {
        self.configuration = configuration
    }

    func loadConfiguration() async -> AppRolloutConfiguration {
        configuration
    }
}
