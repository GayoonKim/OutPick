protocol ChatMediaIndexPersisting: ChatRoomMediaIndexRepositoryProtocol {
    func deleteImageIndexRow(forMessageID messageID: String, idx: Int, inRoom roomID: String?) throws
    func deleteVideoIndexRow(forMessageID messageID: String, idx: Int, inRoom roomID: String?) throws
    func updateVideoDuration(inRoom roomID: String, messageID: String, idx: Int, duration: Double) throws
}
