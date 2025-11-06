//
//  JoinedRoomsStore.swift
//  OutPick
//
//  Created by 김가윤 on 11/6/25.
//

import Foundation
import Combine

actor JoinedRoomsStore {
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
    
    func contains(_ id: String) -> Bool { joined.contains(id) }
    
    func clear() {
        joined.removeAll()
        subject.send([])
    }
}
