import Foundation

struct ChatNavigationStackPolicy {
    enum Action: Equatable {
        case noOp
        case place(retainedIndices: [Int], replacedChatIndices: [Int])
    }

    static func action(
        currentChatRoomIDs: [String?],
        destinationRoomID: String
    ) -> Action {
        if currentChatRoomIDs.last == destinationRoomID {
            return .noOp
        }

        var retainedIndices: [Int] = []
        var replacedChatIndices: [Int] = []

        for (index, roomID) in currentChatRoomIDs.enumerated() {
            if roomID == nil {
                retainedIndices.append(index)
            } else {
                replacedChatIndices.append(index)
            }
        }

        return .place(
            retainedIndices: retainedIndices,
            replacedChatIndices: replacedChatIndices
        )
    }

    static func retainedIndicesAfterClosingRoom(
        sourceIndex: Int,
        isPrecededByRoomCreation: Bool
    ) -> [Int] {
        guard sourceIndex > 0 else { return [] }
        let upperBound = isPrecededByRoomCreation
            ? max(1, sourceIndex - 1)
            : sourceIndex
        return Array(0..<upperBound)
    }
}
