#if DEBUG
import Foundation
import Testing
@testable import OutPick

struct SocketDebugQAConfigurationTests {
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
