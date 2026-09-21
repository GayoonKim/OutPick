# Phase 4 — 화면 주변 선로딩과 재표시 재시도

## 목표

UIKit/SwiftUI 목록에서 확정한 viewport 범위와 표시 계기를 사용한다.

## 변경 파일 후보

- 신규 AvatarViewportPrefetchPolicy.swift, AvatarImagePrefetchController.swift, UIKit/SwiftUI viewport 어댑터 후보. 이미지 처리 로직을 어댑터에 넣지 않는다.
- Chat/Controllers/{ChatViewController,RoomListsCollectionViewController,ChatRoomSettingViewController}.swift 및 실제 참여방/검색 목록 경로.
- Lookbook/Views/PostDetail/{PostCommentsSheetView,PostCommentRepliesSheetView,PostCommentCardView}.swift
- Lookbook/ViewModels/{PostDetailViewModel,PostCommentsViewModel,PostCommentRepliesViewModel}.swift의 기존 전체 avatar prefetch 호출.
- 참고만: LookbookImagePrefetchController/LookbookViewportObserver. 룩북 asset 의존성이 없는 재사용 가능한 부분만 추출 후보로 검토.
- 신규 AvatarViewportPrefetchTests.swift, AvatarImageRetryTests.swift.

## 구현 순서

1. viewport/행 frame/스크롤 방향에서 후보를 계산한다. 진행 방향1.5·반대0.5, 가까운 순 고유24경로, visible 우선.
2. 실제 아바타 미표시 행 제외, 같은 경로의 소비자/저장 정책 합류. 기존 일괄 prefetch와 새 어댑터가 중복 소비자를 계속 만들지 않도록 교체한다.
3. 이탈300ms와 복귀 유지, 종료 즉시 clear를 구현한다. grace용 취소 타이머와 재시도 억제 타이머를 혼동하지 않는다.
4. 실패 작업 entry를 영구 보존하지 않는다. 새 표시 이벤트 token으로 재시도를 허용하고 동일 렌더 pass/동시 이벤트는 합친다.
5. 새로운 상대 메시지가 실제 표시될 때 실패 avatar 재시도를 유발한다. 화면 밖 메시지 도착만으로 모든 실패 avatar를 요청하지 않는다.
6. UIKit 기존 방 커버 prefetch는 다음 작업이므로 아바타 분리 후 기존 기능을 보존한다.

## 완료 기준·검증

위/아래 전환·중복 작성자·빠른 왕복·300ms 직전/직후 해제·화면 종료를 제어 가능한 clock/event로 테스트한다. 5초 대기 없이 재표시 재시도, 화면 유지 중 자동 루프0, 같은 요청 동시 fetch1, visible이 선로딩24 상한으로 막히지 않음. 실패·권한 오류·취소를 구분한다.

## 논의 필요

초기값은 합의 완료. 실기기에서 실제 요구가 다르면 Phase5 증거로 변경을 논의한다. 화면 수명에 대한 새 UX 결정을 임의 추가하지 않는다.
