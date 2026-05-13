//
//  LookbookDebugFailureInjectionStore.swift
//  OutPick
//
//  Created by Codex on 5/13/26.
//

import Foundation

enum LookbookDebugFailureOperation: Hashable {
    case toggleLike
    case toggleSave
    case createComment
    case createReply
    case deleteComment
    case reportComment
    case blockUser
}

enum LookbookDebugFailureInjectionError: LocalizedError, Equatable {
    case injected(operation: LookbookDebugFailureOperation)

    var errorDescription: String? {
        "디버그 실패 주입으로 요청을 실패 처리했습니다."
    }
}

final class LookbookDebugFailureInjectionStore {
    private var failingOperations = Set<LookbookDebugFailureOperation>()
    private let lock = NSLock()

    func setFailure(
        _ operation: LookbookDebugFailureOperation,
        isEnabled: Bool
    ) {
        lock.lock()
        defer { lock.unlock() }

        if isEnabled {
            failingOperations.insert(operation)
        } else {
            failingOperations.remove(operation)
        }
    }

    func isFailureEnabled(for operation: LookbookDebugFailureOperation) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return failingOperations.contains(operation)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }

        failingOperations.removeAll()
    }

    func throwIfNeeded(_ operation: LookbookDebugFailureOperation) throws {
        guard isFailureEnabled(for: operation) else { return }
        throw LookbookDebugFailureInjectionError.injected(operation: operation)
    }
}
