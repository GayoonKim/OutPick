import Testing
@testable import OutPick

struct OutPickAppCheckProviderPolicyTests {
    @Test func debugSimulatorUsesDebugProvider() {
        #expect(
            OutPickAppCheckProviderPolicy.mode(
                isDebugBuild: true,
                isSimulator: true
            ) == .debug
        )
    }

    @Test func debugPhysicalDeviceUsesDebugProvider() {
        #expect(
            OutPickAppCheckProviderPolicy.mode(
                isDebugBuild: true,
                isSimulator: false
            ) == .debug
        )
    }

    @Test func releaseSimulatorKeepsUsingDebugProvider() {
        #expect(
            OutPickAppCheckProviderPolicy.mode(
                isDebugBuild: false,
                isSimulator: true
            ) == .debug
        )
    }

    @Test func releasePhysicalDeviceUsesAppAttestProvider() {
        #expect(
            OutPickAppCheckProviderPolicy.mode(
                isDebugBuild: false,
                isSimulator: false
            ) == .appAttest
        )
    }
}
