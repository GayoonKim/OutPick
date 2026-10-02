import UIKit

@MainActor final class ChatSearchAppLifecycleBinding {
    private var tokens: [NSObjectProtocol] = []
    init(manager: any ChatSearchSessionManaging) {
        for (name, foreground) in [(UIApplication.didEnterBackgroundNotification, false), (UIApplication.didBecomeActiveNotification, true)] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak manager] _ in
                MainActor.assumeIsolated { manager?.setForeground(foreground) }
            })
        }
        manager.setForeground(UIApplication.shared.applicationState != .background)
    }
    deinit { for token in tokens { NotificationCenter.default.removeObserver(token) } }
}
