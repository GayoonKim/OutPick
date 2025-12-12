//
//  PaginationManager.swift
//  OutPick
//
//  Created by 김가윤 on 1/15/25.
//

import Foundation
import FirebaseFirestore

final class PaginationManager: PaginationManagerProtocol {
    var lastFetchedMessageSnapshot: DocumentSnapshot?
    var lastFetchedRoomSnapshot: DocumentSnapshot?
    var lastSearchSnapshot: DocumentSnapshot?
    var currentSearchKeyword: String = ""
    
    func resetPagination() {
        lastFetchedMessageSnapshot = nil
        lastFetchedRoomSnapshot = nil
        lastSearchSnapshot = nil
        currentSearchKeyword = ""
    }
}


