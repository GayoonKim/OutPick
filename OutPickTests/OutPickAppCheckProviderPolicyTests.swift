import Testing
@testable import OutPick

struct OutPickAppCheckProviderPolicyTests {
    @Test func simulatorUsesDebugProvider() {
        #expect(OutPickAppCheckProviderPolicy.mode(isSimulator: true) == .debug)
    }

    @Test func physicalDeviceUsesAppAttestProvider() {
        #expect(OutPickAppCheckProviderPolicy.mode(isSimulator: false) == .appAttest)
    }
}
