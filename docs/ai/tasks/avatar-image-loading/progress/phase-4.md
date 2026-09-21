# Phase 4 — 화면 주변 선로딩·표시 계기 재시도

## 구현 범위

- `AvatarViewportPrefetchPolicy`는 실제 화면 좌표와 스크롤 방향으로 진행1.5/반대0.5화면을 선택한다. 가까운 순·visible 우선으로 고유24경로의 희망 집합을 만들고 중복 경로의 visible 행ID와 저장 정책을 합친다. 같은 경로에서 memoryAndDisk 요구가 있으면 그 정책이 우선한다. 실제 visible 이미지 로딩은 이24개 선택과 독립적이다.
- `AvatarImagePrefetchController`는 희망 집합별 소비자 Task를 관리한다. 이탈 시300ms 해제 대기, 복귀 시 대기 취소·진행 요청 유지, 화면 종료 시 즉시 clear한다.24는 희망 선로딩 집합 상한이며300ms 유예 중인 이전 소비자는 잠시 함께 남을 수 있다. 실제 작업 자원 제한·동일 다운로드 병합은 기존 공용 pipeline을 따른다.
- 완료/실패한 Task 참조를 해제하고, 현재 수요의 결과·visible 이벤트만 기록한다. 일시 실패는 새 visible 행/메시지 또는 영역 복귀 시 즉시 재시도하며, 같은 render/update의 반복으로 재시도하지 않는다. 자동 재시도 타이머·5초 cooldown은 없다.300ms 타이머는 소비자 해제에만 사용한다.
- UIKit `AvatarCollectionViewport`는 collection layout frame과 실제 bounds를 사용한다. ChatViewController·RoomListsCollectionViewController·ChatRoomSettingViewController에 scroll/layout/appear/disappear를 연결했다. 내 채팅 메시지·역할 이벤트 등 아바타가 없는 행은 후보에서 제외했다. 새 상대 메시지가 실제 visible 집합에 들어오면 같은 경로의 보이는 실패 셀에도 재시도 계기를 전달한다. 화면 밖 도착만으로 실패 셀들을 재시도하지 않는다.
- 참여자 목록은 전체 높이의 내부 collection 안에 있어 바깥 participant section frame 하나로 계산하면 안 된다. `ParticipantsSectionParticipantCell.avatarRows(in:)`로 개별 행을 바깥 collection 좌표로 변환하고 실제 visible 행만 직접 표시 요청을 시작한다. 아직 배치되지 않은 section은 행 높이를 추정한다. 기존 Phase3의 바깥 ParticipantListCell cast도 실제 section cell로 수정했다.
- 기존 방장 위임 후보 목록의 아바타도 AvatarImageView와 개별 row frame으로 연결했다. 화면 밖 후보 전체를 즉시 다운로드하던 Task를 제거했다. 새 화면/동작은 추가하지 않았다.
- SwiftUI `AvatarViewportObserver`는 댓글/답글/포스트 상세 대표 댓글의 frame preference와 viewport 높이를 사용한다. 미배치 Lazy 행은 측정된 행 간격의 중앙값으로 추정한다. 실제 가변 행 높이·글자 크기·빠른 스크롤은 Phase5에서 확인한다.
- 댓글/답글/상세 ViewModel의 고정 개수·전체 선로딩과 prefetchedAvatarPaths를 제거했다. 참여자 ViewModel의 일괄 선로딩도 제거하고 사용하지 않는 이미지 DI 인자를 정리했다. 방 목록의 방 커버, 채팅 첨부사진·영상 선로딩은 기존 경로를 보존했다.
- `AvatarImagePresentationState.displayed(eventID:)`는 새 메시지 표시 계기를 한 번만 소비한다. 실패 후 동일 메시지 reconfigure로 반복 호출하지 않는다. `refreshFailure()`는 명시 새로고침에 사용한다.
- 객체 없음/접근 거부는 서비스 세션의 unavailablePaths로 기억하여 셀 재생성/선로딩 영역 재진입에도 실제 서버 자동 요청을 반복하지 않는다. 경로가 달라지면 새 요청, 명시 새로고침은 해당 경로들을 `resetAvatarFailures`로 한 번 해제한 다음 visible/prefetch에 전달한다. 로그아웃/계정 전환은 기록을 지운다. 확대 원본의 사용자 재시도도 명시 해제 후 요청한다.
- 참여 상태가 준비되면 현재 viewport 정책을 재계산하고, 진행 중 memory-only 요청의 디스크 요구는 완료 후 공용 캐시 hit로 승격한다. 실제 멤버십 제거는 수요를 즉시 취소하며 캐시 자체는 남긴다.

## 파일·연결 진입점

- 새 공용 정책/수요: `Chat/Services/ImageLoading/AvatarViewportPrefetchPolicy.swift`, `AvatarImagePrefetchController.swift`.
- SwiftUI frame 어댑터: `Lookbook/Views/Shared/AvatarViewportObserver.swift` → PostCommentsSheetView/PostCommentRepliesSheetView/PostDetailView.
- UIKit: ChatViewController, RoomListsCollectionViewController, ChatRoomSettingViewController → ParticipantsSectionParticipantCell/ParticipantListCell/ChatMessageCell/MessagePreviewView/OwnershipSuccessorRow.
- 오류/수동 재시도: AvatarImageManaging/Service/SessionController/ScopedAvatarImageManager, AvatarImagePresentationState, CommentSafetyAvatarView, UserProfileDetailViewController.
- DI 정리: LookbookContainer, ChatCompositionRoot 및 PostComments/PostCommentReplies/ChatRoomSettingViewModel. 서버 API/데이터/구독 변경은 없다.

## 검증

- 첫 컴파일에서 제거한 이전 한도 필드의 initializer 잔여2개를 발견해 함께 제거했다. 두 번째 `build-for-testing` 통과(`/private/tmp/outpick-avatar-phase4-build2.log`).
- 새 AvatarViewportPrefetchTests8개: 방향 범위,24개 경로/저장 정책 병합, 제어 clock299ms/300ms·빠른 복귀, 실패 후 같은 이벤트 반복0/새 visible 메시지 재시도, 화면 밖 도착 요청0, 진행 중 저장 정책 승격, 화면 종료/이전 실패 경합, 참여 정책 승격 시 일시 실패만 재시도.
- AvatarImagePresentationStateTests에 새 메시지 token 중복 방지·명시적 실패 재시도2개 추가. AvatarImageServiceTests에 unavailable 실제 fetch1회·수동 refresh/새 세션 재허용 추가.
- 첫 통합 회귀: Swift Testing59개/10suite와 viewer XCTest10개 모두 통과(`/private/tmp/outpick-avatar-phase4-tests.log`). 기존 공용 coordinator/캐시·서비스/세션·프로필 관찰·댓글/채팅 표시 데이터 회귀 포함.
- 수동 refresh 단일화·최종 DI 정리 후 통합 재검증도 Swift Testing59개/10suite＋viewer XCTest10개 통과: `/private/tmp/outpick-avatar-phase4-verified-tests.log`.
- 마지막 visible 우선 정렬·참여 정책 승격 재시도 보완 및 테스트 추가 후 집중8개 통과: `/private/tmp/outpick-avatar-phase4-policy-tests.log`, `/tmp/outpick-avatar-build/Logs/Test/Test-OutPick-Development-2026.09.18_22-52-08-+0900.xcresult`. 통합 실행과 집중 실행의 테스트는 중복되므로 합산하지 않는다.
- 검증 환경: OutPick-Development, iPhone17Pro iOS26.5 Simulator(`05397E0E-7170-4B48-A8D2-D60A5B8865FC`), DerivedData `/private/tmp/outpick-avatar-build`. 실제 기기 성능 측정 결과는 아니다.

## 남은 작업

Phase5 실제 스크롤/동적 글자 크기/중첩 참여자 frame·캐시 정책·CPU/메모리/줌·로그아웃 시각 QA가 남는다. 거리/24/300ms/100·75MiB/썸네일3MiB 시작값은 바꾸지 않았다. 측정으로 조정이 필요하면 사용자와 논의한다. 이번 작업은 기기 설치·서버 변경·커밋·PR 없이 코드/문서/Simulator 자동 검증만 수행했다.
