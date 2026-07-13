protocol ChatRoomLocalDataPersisting {
    func cleanTransientRoomData(roomID: String) throws
    func cleanRoomDataAfterExit(roomID: String, currentUserID: String) throws
}
