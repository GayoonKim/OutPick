//
//  JoinedRoomsStore.swift
//  OutPick
//
//  Created by 김가윤 on 11/6/25.
//

import Foundation
import Combine

@MainActor
final class JoinedRoomsStore {
    private(set) var joined: Set<String> = []
    private let subject = CurrentValueSubject<Set<String>, Never>([])
    
    var publisher: AnyPublisher<Set<String>, Never> {
        subject.eraseToAnyPublisher()
    }
    
    func replace(with ids: some Sequence<String>) {
        let new = Set(ids)
        guard new != joined else { return }
        
        joined = new
        subject.send(new)
    }

    func add(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        guard !joined.contains(roomID) else { return }
        joined.insert(roomID)
        subject.send(joined)
    }

    func remove(_ roomID: String) {
        guard !roomID.isEmpty else { return }
        guard joined.remove(roomID) != nil else { return }
        subject.send(joined)
    }
    
    func contains(_ id: String) -> Bool { joined.contains(id) }
    
    func clear() {
        joined.removeAll()
        subject.send([])
    }
}
