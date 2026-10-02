import Foundation
import CoreFoundation
import FirebaseFirestore

final class FirebaseChatSearchRepository: ChatSearchCandidateReading {
    private let transport: any FirebaseChatSearchTransport
    private let maximumSequence: Int64 = 9_007_199_254_740_991

    init(transport: any FirebaseChatSearchTransport) { self.transport = transport }

    func fetchSearchUpperSequence(roomID: String) async throws -> Int64 {
        guard validID(roomID) else { throw ChatSearchFailure.invalidRequest }
        do {
            let snapshot = try await transport.roomFromServer(roomID: roomID)
            try requireServer(snapshot)
            guard let room = snapshot.documents.first, snapshot.documents.count == 1 else { throw ChatSearchFailure.roomClosed }
            guard room.data["isClosed"] as? Bool != true,
                  room.data["lifecycleStatus"] == nil || room.data["lifecycleStatus"] as? String == "active" else {
                throw ChatSearchFailure.roomClosed
            }
            guard let seq = integer(room.data["seq"]), seq >= 0 else { throw ChatSearchFailure.malformedData }
            return seq
        } catch { throw classified(error) }
    }

    func fetchSearchCandidatePage(scope: ChatSearchScope, after: ChatSearchCursor?, limit: Int) async throws -> ChatSearchCandidatePage {
        guard validID(scope.identity.roomID), scope.source == .serverIndex, (1...100).contains(limit),
              scope.upperSeq <= maximumSequence,
              let token = ChatMessageSearchIndex.queryToken(for: scope.normalizedQuery) else { throw ChatSearchFailure.invalidRequest }
        let boundary = try decodeCursor(after, scope: scope)
        let query = FirebaseChatSearchQuery(roomID: scope.identity.roomID, tokenField: token.field, token: token.token,
                                            upperSeq: scope.upperSeq, after: boundary, limit: limit)
        do {
            let snapshot = try await transport.candidatesFromServer(query: query)
            try requireServer(snapshot)
            guard snapshot.documents.count <= limit else { throw ChatSearchFailure.malformedData }
            var previous = boundary
            var candidates: [ChatMessage] = []
            for document in snapshot.documents {
                guard validID(document.id), let seq = integer(document.data["seq"]), seq > 0, seq <= scope.upperSeq else {
                    throw ChatSearchFailure.malformedData
                }
                let current = FirebaseChatSearchBoundary(seq: seq, documentID: document.id)
                if let previous {
                    guard seq < previous.seq || (seq == previous.seq && document.id.utf8.lexicographicallyPrecedes(previous.documentID.utf8)) else {
                        throw ChatSearchFailure.malformedData
                    }
                }
                previous = current
                guard integer(document.data["searchIndexVersion"]) == Int64(ChatMessageSearchIndex.currentVersion) else {
                    throw ChatSearchFailure.incompatibleIndexVersion
                }
                var payload = document.data
                guard payload["roomID"] == nil || payload["roomID"] as? String == scope.identity.roomID,
                      payload["ID"] == nil || payload["ID"] as? String == document.id,
                      let text = payload["msg"] as? String,
                      let type = ChatMessageType(legacyRawValue: payload["messageType"] as? String),
                      [.text, .image, .video].contains(type),
                      payload["serverGenerated"] as? Bool != true else { throw ChatSearchFailure.malformedData }
                let fields = ChatMessageSearchIndex.buildIndexedFields(from: text)
                guard !fields.normalizedText.isEmpty,
                      payload["searchNormalized"] as? String == fields.normalizedText,
                      payload["searchChars"] as? [String] == fields.searchChars,
                      payload["searchNgrams2"] as? [String] == fields.searchNgrams2,
                      (payload[token.field] as? [String])?.contains(token.token) == true else { throw ChatSearchFailure.malformedData }
                payload["ID"] = document.id
                payload["roomID"] = scope.identity.roomID
                guard let message = ChatMessage.from(payload), !message.senderUID.isEmpty, message.sentAt != nil else {
                    throw ChatSearchFailure.malformedData
                }
                // 알려진 삭제는 제외하되 raw cursor는 해당 문서도 소비한다. 차단·삭제 revision은 세션 계층에서 추가 확인한다.
                if !message.isDeleted { candidates.append(message) }
            }
            // 빈 페이지에서는 기존 opaque cursor를 그대로 보존한다.
            let next = snapshot.documents.isEmpty ? after : try previous.map {
                ChatSearchCursor(opaqueValue: try JSONEncoder().encode(CursorPayload(scope: scope, boundary: $0)))
            }
            return ChatSearchCandidatePage(candidates: candidates, nextCursor: next, isExhausted: snapshot.documents.count < limit)
        } catch { throw classified(error) }
    }

    private func decodeCursor(_ cursor: ChatSearchCursor?, scope: ChatSearchScope) throws -> FirebaseChatSearchBoundary? {
        guard let cursor else { return nil }
        guard let payload = try? JSONDecoder().decode(CursorPayload.self, from: cursor.opaqueValue),
              payload.version == 2, payload.sessionID == scope.identity.sessionID, payload.roomID == scope.identity.roomID,
              payload.query == scope.normalizedQuery, payload.upperSeq == scope.upperSeq,
              payload.boundary.seq > 0, payload.boundary.seq <= scope.upperSeq, validID(payload.boundary.documentID) else {
            throw ChatSearchFailure.invalidRequest
        }
        return payload.boundary
    }

    private func requireServer(_ snapshot: FirebaseChatSearchSnapshot) throws {
        guard !snapshot.isFromCache, !snapshot.hasPendingWrites else { throw ChatSearchFailure.transientNetwork }
    }

    private func validID(_ value: String) -> Bool { !value.isEmpty && !value.contains("/") }

    private func integer(_ raw: Any?) -> Int64? {
        guard let number = raw as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value.rounded() == value, value >= 0, value <= Double(maximumSequence) else { return nil }
        return number.int64Value
    }

    private func classified(_ error: Error) -> Error {
        if error is CancellationError || error is ChatSearchFailure { return error }
        let ns = error as NSError
        guard ns.domain == FirestoreErrorDomain, let code = FirestoreErrorCode.Code(rawValue: ns.code) else {
            return ChatSearchFailure.malformedData
        }
        switch code {
        case .permissionDenied, .unauthenticated: return ChatSearchFailure.accessLost
        case .unavailable, .deadlineExceeded, .resourceExhausted: return ChatSearchFailure.transientNetwork
        case .failedPrecondition: return ChatSearchFailure.indexConfiguration
        case .cancelled: return CancellationError()
        case .invalidArgument: return ChatSearchFailure.invalidRequest
        default: return ChatSearchFailure.malformedData
        }
    }
}

private struct CursorPayload: Codable {
    let version: Int
    let sessionID: UUID
    let roomID: String
    let query: String
    let upperSeq: Int64
    let boundary: FirebaseChatSearchBoundary

    init(scope: ChatSearchScope, boundary: FirebaseChatSearchBoundary) {
        version = 2
        sessionID = scope.identity.sessionID
        roomID = scope.identity.roomID
        query = scope.normalizedQuery
        upperSeq = scope.upperSeq
        self.boundary = boundary
    }
}
