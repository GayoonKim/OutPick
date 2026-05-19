//
//  InteractionPinScope.swift
//  OutPick
//
//  Created by Codex on 5/19/26.
//

import Foundation

final class InteractionPinScope {
    private var invalidateAction: (@MainActor () -> Void)?

    init(invalidateAction: @escaping @MainActor () -> Void) {
        self.invalidateAction = invalidateAction
    }

    @MainActor
    func invalidate() {
        guard let invalidateAction else { return }
        self.invalidateAction = nil
        invalidateAction()
    }

    deinit {
        guard let invalidateAction else { return }
        Task { @MainActor in
            invalidateAction()
        }
    }
}
