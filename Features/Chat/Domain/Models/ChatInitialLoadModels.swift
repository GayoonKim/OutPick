//
//  ChatInitialLoadModels.swift
//  OutPick
//
//  Created by Codex on 3/12/26.
//

import Foundation

enum ChatInitialOpenMode: Equatable {
    case unreadAnchor(lastReadSeq: Int64, latestSeq: Int64)
    case latestTail(latestSeq: Int64)

    var latestSeq: Int64 {
        switch self {
        case .unreadAnchor(_, let latestSeq), .latestTail(let latestSeq):
            return latestSeq
        }
    }

    var readBoundarySeq: Int64? {
        switch self {
        case .unreadAnchor(let lastReadSeq, _):
            return lastReadSeq
        case .latestTail:
            return nil
        }
    }
}

struct ChatInitialWindow: Equatable {
    let messages: [ChatMessage]
    let readBoundarySeq: Int64?
    let latestSeq: Int64
    let hasMoreOlder: Bool
    let hasMoreNewer: Bool

    var windowMaxSeq: Int64 {
        messages.map(\.seq).max() ?? 0
    }
}

struct ChatInitialSessionState: Equatable {
    let latestSeq: Int64
    let windowMaxSeq: Int64
    let readBoundarySeq: Int64?
    let hasMoreOlder: Bool
    let hasMoreNewer: Bool

    init(window: ChatInitialWindow) {
        self.latestSeq = window.latestSeq
        self.windowMaxSeq = window.windowMaxSeq
        self.readBoundarySeq = window.readBoundarySeq
        self.hasMoreOlder = window.hasMoreOlder
        self.hasMoreNewer = window.hasMoreNewer
    }
}

struct ChatInitialLoadPolicy: Equatable {
    let latestTailSize: Int
    let unreadAfterSize: Int
    let unreadBeforeContextSize: Int
    let mediaPrefetchConcurrency: Int
}
