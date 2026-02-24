//
//  RoomCreateManaging.swift
//  OutPick
//
//  Created by Codex on 2/25/26.
//

import Foundation

protocol RoomCreateManaging {
    var currentUserEmail: String { get }
    func generateRoomID() -> String
    func checkRoomNameDuplicate(_ roomName: String) async throws -> Bool
    func saveRoom(_ room: ChatRoom) async throws
    func uploadAndCacheRoomImage(pair: DefaultMediaProcessingService.ImagePair, roomID: String) async throws
}
