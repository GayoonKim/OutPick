import Foundation

protocol ChatSearchLocalSnapshot: AnyObject {
    func upperSequence() async throws -> Int64
    func page(upperSeq: Int64, after: ChatSearchCursor?, limit: Int) async throws -> ChatSearchCandidatePage
}

protocol ChatSearchLocalReading {
    func openSearchSnapshot(roomID: String) async throws -> any ChatSearchLocalSnapshot
}
