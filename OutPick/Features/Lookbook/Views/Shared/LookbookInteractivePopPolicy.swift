import SwiftUI

@MainActor
final class LookbookInteractivePopState {
    private(set) var isAllowed: Bool
    var onChange: (() -> Void)?

    init(isAllowed: Bool) {
        self.isAllowed = isAllowed
    }

    func setAllowed(_ isAllowed: Bool) {
        guard self.isAllowed != isAllowed else { return }
        self.isAllowed = isAllowed
        onChange?()
    }
}

private struct LookbookInteractivePopStateKey: EnvironmentKey {
    static let defaultValue: LookbookInteractivePopState? = nil
}

extension EnvironmentValues {
    var lookbookInteractivePopState: LookbookInteractivePopState? {
        get { self[LookbookInteractivePopStateKey.self] }
        set { self[LookbookInteractivePopStateKey.self] = newValue }
    }
}

private struct LookbookInteractivePopDisabledModifier: ViewModifier {
    @Environment(\.lookbookInteractivePopState) private var interactivePopState
    let isDisabled: Bool

    func body(content: Content) -> some View {
        content
            .onAppear {
                interactivePopState?.setAllowed(isDisabled == false)
            }
            .onChange(of: isDisabled) { newValue in
                interactivePopState?.setAllowed(newValue == false)
            }
    }
}

extension View {
    func lookbookInteractivePopDisabled(_ isDisabled: Bool) -> some View {
        modifier(LookbookInteractivePopDisabledModifier(isDisabled: isDisabled))
    }
}
