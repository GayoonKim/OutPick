#if DEBUG
import Foundation
import Testing
@testable import OutPick

struct SocketDebugQAConfigurationTests {
    private let productionURL = URL(string: "https://production.example.com")!

    @Test func validHTTPSOverrideReplacesProductionURL() {
        let configuration = SocketDebugQAConfiguration(environment: [
            SocketDebugQAConfiguration.socketURLKey: " https://candidate.example.com "
        ])

        #expect(configuration.socketURL(productionURL: productionURL).absoluteString == "https://candidate.example.com")
    }

    @Test func missingOrInvalidOverrideFallsBackToProductionURL() {
        let missing = SocketDebugQAConfiguration(environment: [:])
        let invalidScheme = SocketDebugQAConfiguration(environment: [
            SocketDebugQAConfiguration.socketURLKey: "file:///tmp/socket"
        ])
        let missingHost = SocketDebugQAConfiguration(environment: [
            SocketDebugQAConfiguration.socketURLKey: "https://"
        ])

        #expect(missing.socketURL(productionURL: productionURL) == productionURL)
        #expect(invalidScheme.socketURL(productionURL: productionURL) == productionURL)
        #expect(missingHost.socketURL(productionURL: productionURL) == productionURL)
    }

    @Test func ackLossKindsSupportSingleCommaSeparatedAndAllModes() {
        let selected = SocketDebugQAConfiguration(environment: [
            SocketDebugQAConfiguration.dropFirstMessageAckKindKey: " text, images "
        ])
        let all = SocketDebugQAConfiguration(environment: [
            SocketDebugQAConfiguration.dropFirstMessageAckKindKey: "all"
        ])

        #expect(selected.shouldDropFirstMessageAck(kind: "text"))
        #expect(selected.shouldDropFirstMessageAck(kind: "images"))
        #expect(!selected.shouldDropFirstMessageAck(kind: "video"))
        #expect(all.shouldDropFirstMessageAck(kind: "lookbook"))
    }
}
#endif
