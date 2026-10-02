//
//  ChatSearchManaging.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation

enum ChatMessageSearchSource: Equatable, Sendable {
    case serverIndex
    case localOffline
    case localFallbackAfterServerFailure
}

@MainActor protocol ChatSearchSessionManaging: AnyObject, Sendable {
    var snapshot: ChatSearchSessionSnapshot? { get }
    @discardableResult func observe(_ callback: @escaping @MainActor (ChatSearchSessionSnapshot?) -> Void) -> UUID
    func removeObserver(_ id: UUID)
    func search(roomID: String, keyword: String)
    func continueSearch(session: ChatSearchSessionIdentity)
    func prefetchIfNeeded(session: ChatSearchSessionIdentity)
    func prepareNavigation(session: ChatSearchSessionIdentity, direction: ChatSearchDirection) async throws -> ChatSearchPendingNavigation?
    func commitNavigation(_ navigation: ChatSearchPendingNavigation) async throws
    func cancel(session: ChatSearchSessionIdentity) async
    func retry()
    func setForeground(_ foreground: Bool)
    func stop()
}
