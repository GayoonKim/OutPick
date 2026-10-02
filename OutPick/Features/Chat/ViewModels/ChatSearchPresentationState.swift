import Foundation

struct ChatSearchPresentationState: Equatable {
    var title = "검색어를 입력해 주세요"
    var notice: String?
    var isLoading = false
    var showsLoadingIndicator = false
    var canMoveOlder = false
    var canMoveNewer = false
    var actionTitle: String?
    var canContinue = false

    init(snapshot: ChatSearchSessionSnapshot? = nil, moving: Bool = false, movementFailed: Bool = false) {
        guard let snapshot else { return }
        if snapshot.isLimited { notice = "검색 결과 수가 제한될 수 있습니다."; actionTitle = "다시 검색" }
        if case .failed(let failure) = snapshot.count {
            title = failure == .accessLost || failure == .roomClosed ? "검색을 이용할 수 없습니다." : "검색을 완료하지 못했습니다."
            actionTitle = failure == .accessLost || failure == .roomClosed ? nil : "다시 시도"
            return
        }
        if snapshot.isRefreshing || snapshot.isPaused {
            title = "검색 결과를 갱신하고 있습니다."; isLoading = true; showsLoadingIndicator = true; return
        }
        func positionTitle(_ count: Int) -> String {
            guard let ordinal = snapshot.committedOrdinal, ordinal > 0, ordinal <= count else { return String(count) }
            return "\(ordinal)/\(count)"
        }
        switch snapshot.count {
        case .unknown: title = "검색 중…"; isLoading = true; showsLoadingIndicator = true
        case .scanning(let known):
            title = positionTitle(known)
            isLoading = snapshot.isFetching
            canMoveOlder = known > (snapshot.committedOrdinal ?? 0)
            canMoveNewer = (snapshot.committedOrdinal ?? 0) > 1
            if !canMoveOlder, !snapshot.isFetching { actionTitle = "계속 찾기"; canContinue = true }
            else if snapshot.isFetching { actionTitle = nil }
        case .completed(let total):
            title = total == 0 ? "검색 결과 없음" : positionTitle(total)
            canMoveOlder = total > (snapshot.committedOrdinal ?? 0)
            canMoveNewer = (snapshot.committedOrdinal ?? 0) > 1
            if snapshot.isLimited { actionTitle = "다시 검색" }
        case .failed: break
        }
        if movementFailed {
            notice = [notice, "메시지로 이동하지 못했습니다. 다시 시도해 주세요."].compactMap { $0 }.joined(separator: " ")
            actionTitle = "다시 시도"
            canContinue = false
        }
        isLoading = isLoading || moving
    }
}
