//
//  AsyncLoadGate.swift
//  OutPick
//
//  Created by Codex on 6/2/26.
//

import Foundation

@MainActor
struct AsyncLoadGate {
    private(set) var didComplete = false
    private(set) var isRunning = false

    var canUseCachedResult: Bool {
        didComplete
    }

    mutating func beginIfNeeded() -> Bool {
        guard didComplete == false, isRunning == false else { return false }
        isRunning = true
        return true
    }

    mutating func begin() -> Bool {
        guard isRunning == false else { return false }
        isRunning = true
        return true
    }

    mutating func finish(didComplete: Bool) {
        isRunning = false
        if didComplete {
            self.didComplete = true
        }
    }

    mutating func reset() {
        didComplete = false
        isRunning = false
    }
}
